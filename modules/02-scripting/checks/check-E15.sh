# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E15.sh — M02-E15 : CLI medictl avec Typer, lister et décrire les VMs
# À lancer depuis adm01. Lecture seule : medictl n'est lancé qu'avec « vm list » et
# « vm show » ; la référence vient de pvesh (lecture) sur pve01.

title "M02-E15 — CLI medictl : lister et décrire les VMs"
require_cmd jq git

_m02_r="${WB_SRC:-$HOME/src}/outils"
# Le medictl de l'environnement du projet (uv sync), sinon celui du PATH.
_m02_m="$_m02_r/.venv/bin/medictl"
[[ -x "$_m02_m" ]] || _m02_m="$(command -v medictl || echo medictl)"

check_output "medictl --version" '^medictl [0-9]' "$_m02_m" --version
check_cmd "le code ne désactive jamais la vérification TLS" \
  bash -c '! grep -rEn "verify(_ssl)? *= *False" "$1/src"' _ "$_m02_r"
check_cmd "cli.py est fusionné dans main (GitLab)" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/src%2Fmedictl%2Fcli.py?ref=main"

_m02_json="$("$_m02_m" vm list --format json 2>/dev/null || true)"
check_cmd "vm list --format json : un tableau JSON valide sur stdout" jq -e 'type == "array" and length > 0' <<<"$_m02_json"
check_cmd "vm list : adm01 (1001) présente avec son nom" \
  jq -e 'any(.[]; .vmid == 1001 and .name == "adm01")' <<<"$_m02_json"
check_cmd "vm list : le template 9000 est signalé comme tel (template: true)" \
  jq -e 'any(.[]; .vmid == 9000 and .template == true)' <<<"$_m02_json"
check_cmd "vm list : chaque entrée a les clés du contrat (vmid, name, status, node, pool, tags)" \
  jq -e 'all(.[]; has("vmid") and has("name") and has("status") and has("node") and has("pool") and has("tags"))' <<<"$_m02_json"
_m02_ref="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
  jq -c '[.[] | select(.type == "qemu" and .pool == "lab") | .vmid] | sort' 2>/dev/null || true)"
check_cmd "vm list --pool lab : exactement les VMs QEMU du pool lab vues par pve01" bash -c '
  [[ -n "$2" && "$(jq -c "[.[] | select(.pool == \"lab\") | .vmid] | sort" <<<"$1")" == "$2" ]]' _ "$_m02_json" "$_m02_ref"
check_output "vm list (table) : une ligne d'en-tête puis une ligne par VM" '1001[[:space:]]+adm01' \
  "$_m02_m" vm list
check_cmd "vm show 1002 --format json : dns01 avec sa configuration (net0)" bash -c '
  "$1" vm show 1002 --format json 2>/dev/null | jq -e ".name == \"dns01\" and (.config.net0 | type == \"string\")"' _ "$_m02_m"
check_cmd "vm show d'un VMID inexistant : code 1, message sur stderr, stdout vide" bash -c '
  out="$("$1" vm show 999999 2>/dev/null)"; rc=$?
  err="$("$1" vm show 999999 2>&1 >/dev/null)"
  ((rc == 1)) && [[ -z "$out" && -n "$err" ]]' _ "$_m02_m"
