#!/usr/bin/env bash
# version-image.sh — calcule le VMID et la version de la prochaine image dorée (M03-E10).
#
# Usage : outils/version-image.sh debian13|rocky10
# Sortie (une ligne) : « <VMID> <VERSION> », ex. « 9012 20261007-2 »
#   VMID    : premier VMID libre de la plage de la famille (9010-9029 ou 9030-9049),
#             vérifié sur tout le cluster (GET /cluster/nextid?vmid=…), pas seulement le pool ;
#   VERSION : AAAAMMJJ-N, N = 1 + le plus grand N déjà utilisé aujourd'hui dans la famille.
# Codes retour : 0 · 1 erreur d'API · 2 usage · 3 plage pleine (lancer la rotation, M03-E16)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=pve.sh
. "$(dirname "${BASH_SOURCE[0]}")/pve.sh"

famille="${1:-}"
plage="$(pve_famille "$famille")" || { echo "Usage : $0 debian13|rocky10" >&2; exit 2; }
read -r debut fin prefixe <<<"$plage"
pve_charger_acces

jour="$(date +%Y%m%d)"
vms="$(pve_vms)"
# Plus grand N du jour parmi les templates de la famille visibles par le jeton.
n_max="$(jq -r --arg p "$prefixe-$jour-" '
  [.[] | select((.name // "") | startswith($p)) | .name | ltrimstr($p) | tonumber? ] | max // 0' <<<"$vms")"

vmid="$(pve_premier_libre "$debut" "$fin")" \
  || { echo "aucun VMID libre dans $debut-$fin : appliquer la rotation (M03-E16)" >&2; exit 3; }
echo "$vmid $jour-$((n_max + 1))"
