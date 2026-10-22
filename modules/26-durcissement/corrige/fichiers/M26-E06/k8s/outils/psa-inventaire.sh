#!/usr/bin/env bash
# plateforme/k8s — outils/psa-inventaire.sh (M26-E06, SEC-2706)
# Inventaire de Pod Security Admission, espace par espace, et essai d'un profil SANS rien modifier.
#
# Usage :
#   outils/psa-inventaire.sh                         tableau : étiquettes PSA, exception, nombre de pods
#   outils/psa-inventaire.sh --essai restricted      + simulation de enforce=restricted (version v1.36)
#   outils/psa-inventaire.sh --essai baseline --version latest --espace wb-essais
#
# L'essai passe par « kubectl label --dry-run=server » : la requête traverse l'admission (le
# contrôleur PodSecurity renvoie ses avertissements sur les pods existants) mais RIEN n'est écrit.
# Il faut le droit « patch » sur les espaces (compte d'administration, pas celui des checks).
# Les espaces du cluster (kube-system, kube-public, kube-node-lease) sont listés mais jamais essayés.
set -euo pipefail

profil=""
version="v1.36"
seul=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --essai) profil="${2:?profil attendu : privileged, baseline ou restricted}"; shift 2 ;;
    --version) version="${2:?version attendue, ex. v1.36 ou latest}"; shift 2 ;;
    --espace) seul="${2:?nom de l’espace attendu}"; shift 2 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done
case "$profil" in "" | privileged | baseline | restricted) ;; *) echo "Profil inconnu : $profil" >&2; exit 2 ;; esac

for outil in kubectl jq; do
  command -v "$outil" >/dev/null || { echo "$outil requis" >&2; exit 2; }
done

systeme='^(kube-system|kube-public|kube-node-lease)$'
p='pod-security.kubernetes.io'

espaces="$(kubectl get namespaces -o json)"
pods="$(kubectl get pods --all-namespaces -o json | jq -c '[.items[].metadata.namespace] | group_by(.) | map({(.[0]): length}) | add // {}')"

printf '%-26s %-11s %-8s %-11s %-11s %-5s %s\n' ESPACE ENFORCE VERSION AUDIT WARN PODS EXCEPTION
jq -r --arg p "$p" --argjson pods "$pods" --arg seul "$seul" '
  .items[]
  | select($seul == "" or .metadata.name == $seul)
  | .metadata as $m
  | ($m.labels // {}) as $l
  | [ $m.name,
      ($l[$p + "/enforce"] // "absent"),
      ($l[$p + "/enforce-version"] // "-"),
      ($l[$p + "/audit"] // "absent"),
      ($l[$p + "/warn"] // "absent"),
      ($pods[$m.name] // 0 | tostring),
      (($m.annotations // {})["medisphere.internal/exception-psa"] // "")
    ] | @tsv' <<<"$espaces" | sort |
  while IFS=$'\t' read -r nom enforce ver audit warn n exc; do
    printf '%-26s %-11s %-8s %-11s %-11s %-5s %s\n' "$nom" "$enforce" "$ver" "$audit" "$warn" "$n" "$exc"
  done

[[ -n "$profil" ]] || exit 0

echo
echo "== Essai : enforce=$profil, enforce-version=$version (simulation, rien n'est modifié)"
jq -r --arg seul "$seul" '.items[].metadata.name | select($seul == "" or . == $seul)' <<<"$espaces" | sort |
  while read -r nom; do
    if [[ "$nom" =~ $systeme ]]; then
      continue
    fi
    sortie="$(kubectl label --dry-run=server --overwrite namespace "$nom" \
      "$p/enforce=$profil" "$p/enforce-version=$version" 2>&1 >/dev/null || true)"
    if grep -q '^Warning' <<<"$sortie"; then
      echo "-- $nom : NON CONFORME"
      while IFS= read -r ligne; do printf '     %s\n' "$ligne"; done <<<"$sortie"
    elif grep -qi 'error' <<<"$sortie"; then
      echo "-- $nom : ERREUR ($sortie)"
    else
      echo "-- $nom : conforme"
    fi
  done
