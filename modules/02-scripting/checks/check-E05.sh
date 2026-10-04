# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E05.sh — M02-E05 : jq : interroger l'API Proxmox
# À lancer depuis adm01. Applique les filtres de l'apprenant aux fichiers fournis
# (ressources/M02-E05) et à une réponse réelle de l'API (GET uniquement). Lecture seule.

title "M02-E05 — jq : interroger l'API Proxmox"
require_cmd jq curl git

_m02_jq="${WB_SRC:-$HOME/src}/outils/lib/jq"
_m02_res="$ROOT/modules/02-scripting/ressources/M02-E05"

check_output "jq 1.8 sur adm01 (binaire amont prioritaire dans le PATH)" '^jq-1\.([89]|[1-9][0-9])' jq --version

# --- Filtres versionnés -------------------------------------------------------------
for _m02_f in vms-lab bilan-lab ipv4-invite taches-echec; do
  check_cmd "lib/jq/$_m02_f.jq versionné dans plateforme/outils" \
    git -C "$_m02_jq" ls-files --error-unmatch "$_m02_f.jq"
done

# --- Résultats sur les réponses enregistrées -----------------------------------------
check_cmd "vms-lab.jq : résultat attendu sur cluster-resources.json" \
  bash -c 'diff <(jq -r -f "$1/vms-lab.jq" "$2/cluster-resources.json") "$2/attendu/vms-lab.tsv"' \
  _ "$_m02_jq" "$_m02_res"
check_cmd "bilan-lab.jq : résultat attendu sur cluster-resources.json" \
  bash -c 'diff <(jq -S -c -f "$1/bilan-lab.jq" "$2/cluster-resources.json") <(jq -S -c . "$2/attendu/bilan-lab.json")' \
  _ "$_m02_jq" "$_m02_res"
check_cmd "ipv4-invite.jq : résultat attendu sur agent-interfaces.json" \
  bash -c 'diff <(jq -r -f "$1/ipv4-invite.jq" "$2/agent-interfaces.json") "$2/attendu/ipv4-invite.txt"' \
  _ "$_m02_jq" "$_m02_res"
check_cmd "taches-echec.jq : résultat attendu sur taches.json (depuis le 1er octobre 2026)" \
  bash -c 'diff <(jq -r --argjson depuis 1790812800 -f "$1/taches-echec.jq" "$2/taches.json") "$2/attendu/taches-echec.tsv"' \
  _ "$_m02_jq" "$_m02_res"
check_cmd "taches-echec.jq : le paramètre \$depuis est réellement pris en compte" \
  bash -c '[[ $(jq -r --argjson depuis 0 -f "$1/taches-echec.jq" "$2/taches.json" | wc -l) -eq 3 ]]' \
  _ "$_m02_jq" "$_m02_res"

# --- Sur l'API réelle -------------------------------------------------------------------
_m02_env="$HOME/.config/workbook/pve-api.env"
_m02_vms=""
if [[ -r "$_m02_env" ]]; then
  # Sous-shell : les variables du fichier (dont le secret) ne restent pas dans le check.
  # En-tête passé par un descripteur : le secret n'apparaît pas dans la liste des processus.
  _m02_vms="$(
    # shellcheck disable=SC1090
    source "$_m02_env"
    curl -sf --max-time "$WB_TIMEOUT" --cacert "$PVE_CACERT" \
      -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET") \
      "$PVE_API_URL/cluster/resources?type=vm" 2>/dev/null
  )" || _m02_vms=""
fi
if [[ -n "$_m02_vms" ]]; then
  check_output "API réelle : vms-lab.jq liste adm01 (1001)" $'^1001\tadm01\t' \
    bash -c 'jq -r -f "$1/vms-lab.jq" <<<"$2"' _ "$_m02_jq" "$_m02_vms"
  check_cmd "API réelle : vms-lab.jq ne liste pas le template 9000" \
    bash -c '! jq -r -f "$1/vms-lab.jq" <<<"$2" | grep -q "^9000[[:space:]]"' _ "$_m02_jq" "$_m02_vms"
  check_cmd "API réelle : 5 champs séparés par des tabulations sur chaque ligne" \
    bash -c 'jq -r -f "$1/vms-lab.jq" <<<"$2" | awk -F"\t" "NF != 5 { exit 1 }"' _ "$_m02_jq" "$_m02_vms"
  check_output "API réelle : bilan-lab.jq compte au moins 5 VMs portant l'étiquette socle" '^([5-9]|[1-9][0-9]+)$' \
    bash -c 'jq -r -f "$1/bilan-lab.jq" <<<"$2" | jq -r ".par_etiquette.socle // 0"' _ "$_m02_jq" "$_m02_vms"
  # Convention de PLAN.md §4.8 : chaque VM du socle porte « socle » et une étiquette « role-<rôle> ».
  _m02_conv='[.data[] | select(.type == "qemu" and .pool == "lab" and .vmid >= 1000 and .vmid <= 1099)
    | ((.tags // "") | split(";")) as $t
    | ($t | index("socle") != null) and ($t | any(startswith("role-")))]
    | length > 0 and all'
  check_output "API réelle : toutes les VMs du socle (1000-1099) portent socle et une étiquette role-…" '^true$' \
    bash -c 'jq -r "$2" <<<"$1"' _ "$_m02_vms" "$_m02_conv"
else
  check_cmd "API réelle : GET /cluster/resources?type=vm avec ~/.config/workbook/pve-api.env" false
fi
_m02_vms=""
