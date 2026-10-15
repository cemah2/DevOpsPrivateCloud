#!/usr/bin/env bash
# plateforme/k8s — outils/derive.sh (M14-E23)
# Dérive entre le dépôt et le cluster, dans les deux sens, SANS rien modifier :
#   1. dépôt → cluster : « kubectl diff --server-side » de chaque dossier (champs modifiés à la main) ;
#   2. cluster → dépôt : objets dont un champ a été posé par le gestionnaire de ce dépôt
#      (--field-manager) mais qui ne figurent plus dans aucun fichier (supprimés du dépôt, pas du
#      cluster), pour chaque type d'objet présent dans le dépôt.
# Code de sortie : 0 aucune dérive, 1 dérive trouvée, 2 erreur.
# Usage : outils/derive.sh CONTEXTE GESTIONNAIRE DOSSIER...   (task derive)
set -uo pipefail

(($# >= 3)) || { echo "usage : derive.sh CONTEXTE GESTIONNAIRE DOSSIER..." >&2; exit 2; }
contexte="$1"; gestionnaire="$2"; shift 2
dossiers=()
for d in "$@"; do [[ -d "$d" ]] && dossiers+=("$d"); done
k() { kubectl --context "$contexte" "$@"; }
derive=0

echo "== 1. Dépôt → cluster (kubectl diff) =="
for d in "${dossiers[@]}"; do
  # --force-conflicts : un champ repris à la main par un autre gestionnaire (kubectl edit, patch) est un
  # CONFLIT pour le server-side apply ; sans cette option, diff s'arrête en erreur au lieu de le montrer.
  sortie="$(k diff --server-side --force-conflicts --field-manager="$gestionnaire" -R -f "$d" 2>&1)"
  code=$?
  if ((code == 1)); then
    echo "-- $d : différences"; printf '%s\n' "$sortie"; derive=1
  elif ((code > 1)); then
    echo "-- $d : erreur de kubectl diff" >&2; printf '%s\n' "$sortie" >&2; exit 2
  else
    echo "-- $d : conforme"
  fi
done

echo "== 2. Cluster → dépôt (objets posés par « $gestionnaire » absents du dépôt) =="
attendus="$(find "${dossiers[@]}" -name '*.yaml' -print0 \
  | xargs -0 yq e -N '[.kind, (.metadata.namespace // "-"), .metadata.name] | join("/")' 2>/dev/null \
  | grep -v '^null' | sort -u)"
types="$(cut -d/ -f1 <<<"$attendus" | sort -u)"
presents=""
for t in $types; do
  presents+="$(k get "$t" -A -o json --show-managed-fields 2>/dev/null | jq -r --arg g "$gestionnaire" '.items[]
    | select(any(.metadata.managedFields[]?; .manager == $g))
    | [.kind, (.metadata.namespace // "-"), .metadata.name] | join("/")')"$'\n'
done
orphelins="$(comm -13 <(printf '%s\n' "$attendus") <(printf '%s' "$presents" | grep -v '^$' | sort -u))"
if [[ -n "$orphelins" ]]; then
  echo "Objets du cluster gérés par ce dépôt mais absents des fichiers (à supprimer par MR ou à réintégrer) :"
  printf '  %s\n' "${orphelins//$'\n'/$'\n  '}"
  derive=1
else
  echo "aucun"
fi

((derive)) && echo "Dérive constatée." || echo "Aucune dérive."
exit "$derive"
