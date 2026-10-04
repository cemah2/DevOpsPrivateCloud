# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E13.sh — M02-E13 : verrous, fichiers temporaires et exécutions concurrentes
# À lancer depuis adm01. Le contrôle lance TON ms-export-config dans un dossier temporaire
# (MS_EXPORT_DIR, MS_LOCK_DIR) : l'API Proxmox n'est que lue. Le dossier est supprimé ensuite.

title "M02-E13 — Verrous, fichiers temporaires et exécutions concurrentes"
require_cmd jq flock shellcheck git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_exp="$_m02_r/bin/ms-export-config"
_m02_snap="$_m02_r/bin/ms-snapshot"

check_cmd "lib/ms-commun.sh fournit lock_or_die" \
  bash -c 'source "$1" && declare -F lock_or_die' _ "$_m02_r/lib/ms-commun.sh"
check_cmd "bin/ms-export-config présent et exécutable" test -x "$_m02_exp"
check_cmd "ms-export-config et la bibliothèque passent ShellCheck" \
  bash -c 'cd "$1" && shellcheck -x bin/ms-export-config lib/ms-commun.sh' _ "$_m02_r"
check_cmd "ms-export-config est fusionné dans main (GitLab)" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/bin%2Fms-export-config?ref=main"
check_cmd "ms-snapshot prend lui aussi un verrou" grep -Eq '^[^#]*lock_or_die' "$_m02_snap"

_m02_tmp="$(mktemp -d)"
export MS_LOCK_DIR="$_m02_tmp/verrous" MS_EXPORT_DIR="$_m02_tmp/exports"
mkdir -p "$MS_LOCK_DIR"

# --- Exclusion mutuelle : le contrôle tient lui-même le verrou, l'outil doit refuser (3) ---
flock "$MS_LOCK_DIR/ms-export-config.lock" sleep 30 &
_m02_pid=$!
sleep 0.5
check_cmd "verrou tenu : ms-export-config refuse avec le code 3 et n'écrit rien" bash -c '
  rc=0; "$1" </dev/null >/dev/null 2>&1 || rc=$?; ((rc == 3)) && [[ ! -e "$2/dernier" ]]' _ "$_m02_exp" "$MS_EXPORT_DIR"
flock "$MS_LOCK_DIR/ms-snapshot.lock" sleep 30 &
_m02_pid2=$!
sleep 0.5
check_cmd "verrou tenu : ms-snapshot --dry-run refuse avec le code 3" bash -c '
  rc=0; "$1" --dry-run 2020 </dev/null >/dev/null 2>&1 || rc=$?; ((rc == 3))' _ "$_m02_snap"
kill "$_m02_pid" "$_m02_pid2" 2>/dev/null || true
wait "$_m02_pid" "$_m02_pid2" 2>/dev/null || true

# --- Export réel (lectures API) dans le dossier temporaire ------------------------------------
_m02_rc=0
"$_m02_exp" </dev/null >/dev/null 2>&1 || _m02_rc=$?
check_cmd "verrou libre : export réussi (code 0)" test "$_m02_rc" -eq 0
check_cmd "« dernier » est un lien vers un export horodaté AAAAMMJJ-HHMMSS" bash -c '
  [[ -L "$1/dernier" && "$(readlink "$1/dernier")" =~ ^[0-9]{8}-[0-9]{6}$ && -d "$1/dernier/" ]]' _ "$MS_EXPORT_DIR"
check_cmd "l'export contient la configuration de adm01 (1001-adm01.json, JSON valide)" \
  bash -c 'jq -e . "$1/dernier/1001-adm01.json"' _ "$MS_EXPORT_DIR"
check_cmd "l'export contient au moins 5 configurations de VM" \
  bash -c '(($(find "$1/dernier/" -name "[0-9]*-*.json" | wc -l) >= 5))' _ "$MS_EXPORT_DIR"
check_cmd "aucun dossier ou fichier temporaire ne reste dans MS_EXPORT_DIR" \
  bash -c '[[ -z "$(find "$1" -mindepth 1 -maxdepth 1 -name ".*" -print -quit)" ]]' _ "$MS_EXPORT_DIR"
check_cmd "aucun fichier temporaire de l'outil ne reste dans /tmp" \
  bash -c '[[ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -user "$(id -u)" -newer "$1" -name "tmp.*" ! -path "$1" -print -quit 2>/dev/null)" ]]' _ "$_m02_tmp"
unset MS_LOCK_DIR MS_EXPORT_DIR
rm -rf -- "${_m02_tmp:?}"

# --- Ton propre export (réel, dans le dossier par défaut) --------------------------------------
check_cmd "un export réel existe : ~/exports/config-vms/dernier" test -d "$HOME/exports/config-vms/dernier/"
