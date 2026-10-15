#!/usr/bin/env bash
# =============================================================================
# outils/certificats-echeances.sh — plateforme/k8s (M14-E26, SEC-1526, RB-143) : échéances de TOUS
# les certificats de k8s-par1, depuis adm01, en lecture seule.
#
#  - nœuds de contrôle : /etc/kubernetes/pki/**/*.crt et certificats incorporés aux kubeconfigs de
#    kubeadm (admin.conf, super-admin.conf, controller-manager.conf, scheduler.conf) ;
#  - tous les nœuds : certificat client du kubelet (/var/lib/kubelet/pki/kubelet-client-current.pem)
#    et certificat de SERVICE présenté sur le port 10250 (vérifié avec la CA du cluster).
# Sortie : une ligne par certificat (jours restants, nœud, nom) ; code 1 si l'un expire sous
# SEUIL jours (défaut 30) ou si un contrôle est impossible, 0 sinon. Rien n'est modifié.
# Usage : outils/certificats-echeances.sh [--seuil JOURS] [--quiet]
# =============================================================================
set -Eeuo pipefail

seuil=30
quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seuil) seuil="${2:?}"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
[[ "$seuil" =~ ^[0-9]+$ ]] || { echo "seuil invalide : $seuil" >&2; exit 2; }

read -r -a cp <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a travailleurs <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
zone=par1.medisphere.internal
ko=0
travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT

ligne() { # ligne JOURS NŒUD NOM
  local etat=OK
  if [[ ! "$1" =~ ^-?[0-9]+$ ]]; then etat=KO; ko=1
  elif (( $1 < seuil )); then etat=KO; ko=1; fi
  if (( ! quiet )) || [[ $etat == KO ]]; then printf '%-3s %6s j  %-9s %s\n' "$etat" "$1" "$2" "$3"; fi
}

# Script exécuté sur chaque nœud (sudo) : « NOM FIN » par certificat, FIN en secondes depuis l'époque.
# shellcheck disable=SC2016  # évalué sur le nœud
distant='
set -u
fin() { date -d "$(openssl x509 -noout -enddate | cut -d= -f2)" +%s; }
for f in $(find /etc/kubernetes/pki -name "*.crt" 2>/dev/null | sort); do
  printf "%s %s\n" "${f#/etc/kubernetes/pki/}" "$(fin <"$f")"
done
for k in admin super-admin controller-manager scheduler; do
  c=/etc/kubernetes/$k.conf
  [ -r "$c" ] || continue
  sed -n "s/^ *client-certificate-data: *//p" "$c" | head -1 | base64 -d | { printf "%s %s\n" "$k.conf" "$(fin)"; }
done
k=/var/lib/kubelet/pki/kubelet-client-current.pem
[ -r "$k" ] && printf "%s %s\n" kubelet-client "$(fin <"$k")"
true'

maintenant=$(date +%s)
for n in "${cp[@]}" "${travailleurs[@]}"; do
  if ! ssh -o BatchMode=yes "$n" "sudo -n bash -c '$distant'" >"$travail/$n" 2>/dev/null || [[ ! -s "$travail/$n" ]]; then
    ligne "?" "$n" "lecture des certificats impossible (SSH ou sudo)"
    continue
  fi
  while read -r nom fin; do
    ligne $(( (fin - maintenant) / 86400 )) "$n" "$nom"
  done <"$travail/$n"
done

# Certificats de service des kubelets, tels que servis, vérifiés avec la CA du cluster.
ca="$travail/ca.crt"
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d >"$ca"
for n in "${cp[@]}" "${travailleurs[@]}"; do
  pem="$(timeout 10 openssl s_client -connect "$n.$zone:10250" -servername "$n" -CAfile "$ca" -verify_hostname "$n" -verify_return_error \
        </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || pem=""
  if [[ -z "$pem" ]]; then
    ligne "?" "$n" "kubelet:10250 — certificat de service absent ou non signé par la CA du cluster"
    continue
  fi
  fin=$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)
  ligne $(( (fin - maintenant) / 86400 )) "$n" "kubelet-serving (port 10250)"
done

exit "$ko"
