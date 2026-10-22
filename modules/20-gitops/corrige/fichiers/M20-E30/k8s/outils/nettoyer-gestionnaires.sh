#!/usr/bin/env bash
# outils/nettoyer-gestionnaires.sh (plateforme/k8s) — M20-E30, SEC-2130.
# Retire des managedFields d'un objet les entrées des gestionnaires humains ou de CI (kubectl,
# kubectl-*, helm, gitlab*, agentk) laissées par le M17 et le M19, SANS modifier aucun champ de
# l'objet : on retire une ENTRÉE de propriété (patch JSON sur metadata.managedFields), on n'applique
# pas de configuration vide (qui SUPPRIMERAIT les champs dont ce gestionnaire était seul propriétaire).
#
# Usage : outils/nettoyer-gestionnaires.sh ESPACE TYPE/NOM [--appliquer]
#   sans --appliquer : essai côté serveur (--dry-run=server), affiche les gestionnaires avant/après et
#   la différence de .spec (doit être VIDE) ; avec --appliquer : la même chose, pour de vrai.
# Le patch porte le gestionnaire « nettoyage-gestionnaires » (jamais « kubectl-patch »).
# Après nettoyage, les champs encore déclarés dans Git restent possédés par argocd-controller ; les
# autres n'ont plus de propriétaire : la prochaine synchronisation d'Argo CD les reprend s'ils sont
# dans Git, sinon ils restent tels quels (aucune suppression).
set -Eeuo pipefail

contexte="${KUBE_CONTEXTE:-k8s-par1}"
espace="${1:-}"; objet="${2:-}"; mode="${3:-essai}"
[[ -n "$espace" && -n "$objet" ]] || { echo "usage : $0 ESPACE TYPE/NOM [--appliquer]" >&2; exit 2; }
motif='^(kubectl|kubectl-.*|helm|gitlab.*|agentk)$'
k() { kubectl --context "$contexte" -n "$espace" "$@"; }

avant="$(k get "$objet" -o json)"
echo "Gestionnaires avant :"
jq -r '.metadata.managedFields[] | "  \(.manager) (\(.operation)\(if .subresource then ", " + .subresource else "" end))"' <<<"$avant"

# Indices à retirer, du plus grand au plus petit (un « remove » décale les suivants) ; chaque retrait
# est précédé d'un « test » sur le nom du gestionnaire : si l'objet a changé entre-temps, rien n'est fait.
patch="$(jq -c --arg m "$motif" '
  [.metadata.managedFields | to_entries[] | select(.value.manager | test($m))]
  | sort_by(-.key)
  | map([{op: "test", path: "/metadata/managedFields/\(.key)/manager", value: .value.manager},
         {op: "remove", path: "/metadata/managedFields/\(.key)"}])
  | add // []' <<<"$avant")"
if [[ "$patch" == "[]" ]]; then
  echo "Rien à retirer sur $espace/$objet."
  exit 0
fi

dry=(--dry-run=server)
[[ "$mode" == "--appliquer" ]] && dry=()
apres="$(k patch "$objet" --type json -p "$patch" --field-manager=nettoyage-gestionnaires "${dry[@]}" -o json)"

echo "Gestionnaires après :"
jq -r '.metadata.managedFields[] | "  \(.manager) (\(.operation))"' <<<"$apres"
if diff <(jq -S .spec <<<"$avant") <(jq -S .spec <<<"$apres") >/dev/null; then
  echo "spec inchangée : OK"
else
  echo "ATTENTION : la spec changerait (ou a changé) :" >&2
  diff <(jq -S .spec <<<"$avant") <(jq -S .spec <<<"$apres") >&2 || true
  exit 1
fi
[[ "$mode" == "--appliquer" ]] && echo "[OK] $espace/$objet nettoyé." || echo "Essai seulement : relance avec --appliquer."
