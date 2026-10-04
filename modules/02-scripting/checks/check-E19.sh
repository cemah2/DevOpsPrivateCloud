# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E19.sh — M02-E19 : configuration et secrets des outils
# À lancer depuis adm01. Lecture seule. Le secret du jeton est lu dans un sous-shell et
# comparé par « grep -f <(…) » : il n'apparaît jamais dans la liste des processus.

title "M02-E19 — Configuration et secrets des outils"
require_cmd git stat

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_m="$_m02_r/.venv/bin/medictl"
[[ -x "$_m02_m" ]] || _m02_m="$(command -v medictl || echo medictl)"
_m02_env="$HOME/.config/workbook/pve-api.env"
_m02_tmp="$(mktemp -d)"
chmod 700 "$_m02_tmp"

# _m02_sans_secret FICHIER — vrai si FICHIER ne contient pas le secret du jeton
_m02_sans_secret() {
  local s
  # shellcheck source=/dev/null
  s="$(. "$_m02_env" >/dev/null 2>&1; printf '%s' "${PVE_TOKEN_SECRET:-}")"
  [[ -n "$s" ]] && ! grep -qF -f <(printf '%s\n' "$s") -- "$1"
}

check_output "dossier .config/workbook en mode 700" '^700$' stat -c '%a' "$HOME/.config/workbook"
check_output "pve-api.env en mode 600" '^600$' stat -c '%a' "$_m02_env"
check_cmd "pve-api.env n'est dans aucun dépôt Git" \
  bash -c '! git -C "$(dirname "$1")" rev-parse --is-inside-work-tree >/dev/null 2>&1' _ "$_m02_env"

# --- medictl config : configuration effective, secret masqué -----------------------------------
"$_m02_m" config </dev/null >"$_m02_tmp/config" 2>&1 || true
check_output "medictl config affiche le jeton utilisé" 'wb-automation@pve!lab' cat "$_m02_tmp/config"
check_cmd "medictl config n'affiche pas le secret" _m02_sans_secret "$_m02_tmp/config"
check_output "une variable d'environnement PVE_* l'emporte sur le fichier" 'check-e19' \
  env PVE_NODE=check-e19 "$_m02_m" config

# --- Fichier trop ouvert : refus, sans appel à l'API ----------------------------------------------
install -m 644 "$_m02_env" "$_m02_tmp/ouvert.env" 2>/dev/null || true
check_cmd "fichier d'accès en mode 644 : medictl refuse (code 1, message sur stderr)" bash -c '
  err="$(MEDICTL_ENV_FILE="$2" "$1" vm list 2>&1 >/dev/null)"; rc=$?; ((rc == 1)) && [[ -n "$err" ]]' \
  _ "$_m02_m" "$_m02_tmp/ouvert.env"

# --- Jamais de secret à l'écran, même en mode le plus bavard --------------------------------------
"$_m02_m" -vvv vm list --format json </dev/null >"$_m02_tmp/bavard" 2>&1 || true
check_cmd "medictl -vvv vm list : le secret n'apparaît ni sur stdout ni sur stderr" _m02_sans_secret "$_m02_tmp/bavard"

# --- Jamais de secret dans le dépôt, historique compris --------------------------------------------
git -C "$_m02_r" log --all -p >"$_m02_tmp/historique" 2>/dev/null || true
check_cmd "le secret n'apparaît nulle part dans l'historique de plateforme/outils" \
  _m02_sans_secret "$_m02_tmp/historique"
check_cmd "le dépôt ignore les fichiers *.env" git -C "$_m02_r" check-ignore -q pve-api.env
rm -rf -- "${_m02_tmp:?}"
