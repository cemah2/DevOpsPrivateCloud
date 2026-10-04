# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E16.sh — M02-E16 : medictl vm create/destroy avec garde-fous
# À lancer depuis adm01, après le cycle de l'exercice (2021 créée puis détruite, 2020 détruite).
# Prudence : les refus ne sont testés que sur des VMID LIBRES (vérifiés sur pve01 avant) :
# même si un garde-fou manquait, aucune VM existante ne pourrait être touchée.

title "M02-E16 — medictl vm create/destroy avec garde-fous"
require_cmd jq git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_m="$_m02_r/.venv/bin/medictl"
[[ -x "$_m02_m" ]] || _m02_m="$(command -v medictl || echo medictl)"

# _m02_libre VMID — vrai si aucune VM de pve01 ne porte ce VMID
_m02_libre() { ! remote "$WB_PVE_HOST" "qm status $1" >/dev/null 2>&1; }
# _m02_code ATTENDU COMMANDE...
_m02_code() {
  local attendu="$1" rc=0
  shift
  "$@" </dev/null >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq "$attendu" ]]
}

check_cmd "les garde-fous sont dans le code (garde_fous.py ou équivalent) et fusionnés dans main" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/src%2Fmedictl%2Fcli.py?ref=main"
check_output "vm create --help mentionne --vmid, --template, --vnet et --wait/--no-wait" \
  '--no-wait' "$_m02_m" vm create --help

# --- Refus (code 3) sur des VMID libres ------------------------------------------------------
for _m02_v in 1099 4242 9099; do
  if _m02_libre "$_m02_v"; then
    check_cmd "vm destroy $_m02_v --yes (plage interdite) : refus, code 3" _m02_code 3 "$_m02_m" vm destroy "$_m02_v" --yes
  else
    skip "refus de destruction de $_m02_v" "VMID occupé sur pve01 : test non joué par prudence"
  fi
done
if _m02_libre 2029; then
  check_cmd "vm create avec un nom invalide (M02_TEST) : refus, code 3" \
    _m02_code 3 "$_m02_m" vm create M02_TEST --vmid 2029 --no-wait
else
  skip "refus d'un nom invalide" "VMID 2029 occupé : test non joué"
fi
check_cmd "vm create sans --vmid : erreur d'usage, code 2" _m02_code 2 "$_m02_m" vm create m02-test
check_cmd "aucune VM n'a été créée par ces essais (1099, 4242, 9099 toujours libres)" \
  bash -c 'for v in 1099 4242 9099; do ssh -o BatchMode=yes "$1" "qm status $v" >/dev/null 2>&1 && exit 1; done; exit 0' _ "$WB_PVE_HOST"

# --- Traces du cycle create/destroy dans le journal des tâches -------------------------------
_m02_taches="$(remote "$WB_PVE_HOST" 'pvesh get /nodes/$(hostname)/tasks --userfilter wb-automation --limit 1000 --output-format json' 2>/dev/null || true)"
check_cmd "pve01 : une VM 2021-2029 démarrée par le jeton (qmstart OK)" jq -e \
  'any(.[]; .type == "qmstart" and .status == "OK" and ((.id | tonumber? // 0) | . >= 2021 and . <= 2029))' <<<"$_m02_taches"
check_cmd "pve01 : une VM 2021-2029 détruite par le jeton (qmdestroy OK)" jq -e \
  'any(.[]; .type == "qmdestroy" and .status == "OK" and ((.id | tonumber? // 0) | . >= 2021 and . <= 2029))' <<<"$_m02_taches"
check_cmd "pve01 : la VM 2020 (m02-cobaye) détruite par le jeton (qmdestroy OK)" jq -e \
  'any(.[]; .type == "qmdestroy" and .status == "OK" and .id == "2020")' <<<"$_m02_taches"
check_cmd "plus aucune VM jetable 2020-2029 sur pve01" bash -c '
  ! ssh -o BatchMode=yes "$1" "qm list" 2>/dev/null | awk "NR > 1 {print \$1}" | grep -Eq "^202[0-9]$"' _ "$WB_PVE_HOST"
