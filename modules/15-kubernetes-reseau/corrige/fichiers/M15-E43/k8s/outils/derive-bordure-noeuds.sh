#!/usr/bin/env bash
# derive-bordure-noeuds.sh — complète outils/derive-reseau.sh (M15-E23, qui compare le cluster au
# dépôt : kubectl diff, values Helm, étiquettes) par ce qu'il ne voit pas : la configuration courante
# de FRR sur la bordure et les pare-feu des nœuds (M15-E38 v5, M15-E42 v1). Lecture seule.
#
# Usage (depuis la racine du clone de plateforme/k8s, sur adm01) :
#   outils/derive-bordure-noeuds.sh [--bordure] [--noeuds]     (sans option : les deux)
# Code de sortie : 0 aucun écart, 1 au moins un écart, 2 erreur d'usage.
# Bordure : « show running-config » de FRR comparé à /etc/frr/frr.conf (généré par le rôle frr).
# Nœuds : tables nftables qui ne sont ni à Cilium, ni au backend nft d'iptables (kubelet, Cilium).
# Planifié avec derive-reseau.sh (task reseau:derive) : un écart = une correction à reporter dans
# le dépôt, ou une dérive à retirer.
set -euo pipefail

PASSERELLES=(gw01 gw02)
read -r -a NOEUDS <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03} ${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
ecarts=0

ecart() { printf 'ÉCART  %s\n' "$*"; ecarts=$((ecarts + 1)); }
ok() { printf 'ok     %s\n' "$*"; }

normaliser_frr() {
  # Retire l'en-tête et les lignes sans signification (version, commentaires, lignes vides), puis
  # trie : FRR ne réécrit pas toujours les sections dans l'ordre du fichier ; le tri garde toute
  # ligne ajoutée, retirée ou modifiée (non testé sur toutes les versions : un faux positif dû à
  # une valeur par défaut affichée par « show running-config » est à ajouter au filtre).
  sed -E '/^(Building configuration|Current configuration|frr version|frr defaults|!|end$|$)/d; s/[[:space:]]+$//' | sort
}

bordure() {
  local g courant fichier
  for g in "${PASSERELLES[@]}"; do
    if ! courant="$(ssh -o BatchMode=yes "$g" "sudo -n vtysh -c 'show running-config'" 2>/dev/null)" \
      || ! fichier="$(ssh -o BatchMode=yes "$g" 'sudo -n cat /etc/frr/frr.conf' 2>/dev/null)"; then
      ecart "$g : lecture de FRR impossible (SSH ou sudo)"
      continue
    fi
    if diff <(normaliser_frr <<<"$fichier") <(normaliser_frr <<<"$courant") >/dev/null; then
      ok "$g : configuration courante de FRR = /etc/frr/frr.conf"
    else
      ecart "$g : configuration courante de FRR différente du fichier :"$'\n'"$(diff <(normaliser_frr <<<"$fichier") <(normaliser_frr <<<"$courant") || true)"
    fi
  done
}

noeuds() {
  local n tables
  for n in "${NOEUDS[@]}"; do
    # Tables attendues : celles de Cilium (cilium_*) et du backend nft d'iptables (ip/ip6 filter,
    # nat, mangle, raw, security) posées par kubelet et Cilium.
    if ! tables="$(ssh -o BatchMode=yes "$n" 'sudo -n nft list tables 2>/dev/null' 2>/dev/null)"; then
      ecart "$n : lecture de nftables impossible (SSH ou sudo)"
      continue
    fi
    tables="$(grep -Ev '^table (ip|ip6) (filter|nat|mangle|raw|security)$|^table [a-z0-9]+ cilium' <<<"$tables" || true)"
    if [[ -n "$tables" ]]; then
      ecart "$n : tables nftables étrangères : $(tr '\n' ' ' <<<"$tables")"
    else
      ok "$n : aucune table nftables étrangère"
    fi
  done
}

main() {
  local faire=()
  while (($#)); do
    case "$1" in
      --bordure | --noeuds) faire+=("${1#--}") ;;
      -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
      *) echo "option inconnue : $1" >&2; exit 2 ;;
    esac
    shift
  done
  ((${#faire[@]})) || faire=(bordure noeuds)
  local f
  for f in "${faire[@]}"; do "$f"; done
  echo
  if ((ecarts)); then
    echo "$ecarts écart(s) : chaque écart est soit une correction à reporter dans le dépôt, soit une dérive à retirer."
    exit 1
  fi
  echo "Aucun écart."
}

main "$@"
