# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E21.sh — M02-E21 : générer l'inventaire du socle depuis l'API (LIBRE)
# À lancer depuis adm01. Lecture seule : « medictl inventaire » sans option d'écriture,
# et lecture de docs/socle/inventaire.md sur la branche main de plateforme/medisphere.
# Le format est libre : seuls le contrat JSON et la présence des données sont contrôlés.

title "M02-E21 — Générer l'inventaire du socle depuis l'API"
require_cmd jq

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_m="$_m02_r/.venv/bin/medictl"
[[ -x "$_m02_m" ]] || _m02_m="$(command -v medictl || echo medictl)"

_m02_debut=$SECONDS
_m02_json="$("$_m02_m" inventaire --format json </dev/null 2>/dev/null || true)"
_m02_duree=$((SECONDS - _m02_debut))
check_cmd "inventaire --format json : JSON valide, clés vmid, name, status, tags et ipv4 (liste)" jq -e \
  'type == "array" and length > 0 and all(.[]; has("vmid") and has("name") and has("status") and has("tags") and (.ipv4 | type == "array"))' \
  <<<"$_m02_json"
check_cmd "inventaire produit en moins de 60 s (${_m02_duree} s)" test "$_m02_duree" -lt 60
for _m02_c in "1000 10.10.10.1" "1001 10.10.10.10" "1002 10.10.20.10" "1004 10.10.20.12" "1007 10.10.20.15"; do
  read -r _m02_v _m02_ip <<<"$_m02_c"
  check_cmd "VM $_m02_v présente avec l'adresse $_m02_ip (agent QEMU)" jq -e --argjson v "$_m02_v" --arg ip "$_m02_ip" \
    'any(.[]; .vmid == $v and (.ipv4 | index($ip)))' <<<"$_m02_json"
done
check_cmd "seules les VMs étiquetées « socle » sont inventoriées (pas le template 9000)" \
  jq -e 'all(.[]; .vmid != 9000 and (.tags | tostring | test("socle")))' <<<"$_m02_json"
check_cmd "sortie Markdown déterministe (deux exécutions identiques)" bash -c '
  a="$("$1" inventaire --format markdown 2>/dev/null)" && b="$("$1" inventaire --format markdown 2>/dev/null)" &&
  [[ -n "$a" && "$a" == "$b" ]]' _ "$_m02_m"

# --- Le document de référence, sur main ----------------------------------------------------------
_m02_doc="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Finventaire.md/raw?ref=main" 2>/dev/null || true)"
check_cmd "docs/socle/inventaire.md de main : git01 (1004) et runner01 (1007) avec leurs adresses" bash -c '
  grep -E "1004.*10\.10\.20\.12" <<<"$1" >/dev/null && grep -E "1007.*10\.10\.20\.15" <<<"$1" >/dev/null' _ "$_m02_doc"
check_cmd "inventaire.md de main = sortie actuelle de medictl (lignes du tableau généré)" bash -c '
  gen="$("$1" inventaire --format markdown 2>/dev/null | grep -E "^\| *[0-9]{4} ")" || exit 1
  [[ -n "$gen" ]] && grep -qxFf <(printf "%s\n" "$gen") <<<"$2" &&
  [[ "$(grep -cxFf <(printf "%s\n" "$gen") <<<"$2")" -eq "$(grep -c . <<<"$gen")" ]]' _ "$_m02_m" "$_m02_doc"
