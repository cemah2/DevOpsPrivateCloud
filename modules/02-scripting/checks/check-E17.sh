# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E17.sh — M02-E17 : erreurs, journalisation et reprises en Python
# À lancer depuis adm01. Lecture seule : « medictl vm list » est lancé avec des copies
# jetables (mode 600) du fichier d'accès, volontairement faussées (secret, adresse, CA).

title "M02-E17 — Erreurs, journalisation et reprises en Python"
require_cmd jq

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_m="$_m02_r/.venv/bin/medictl"
[[ -x "$_m02_m" ]] || _m02_m="$(command -v medictl || echo medictl)"
_m02_env="${MEDICTL_ENV_FILE:-$HOME/.config/workbook/pve-api.env}"
_m02_tmp="$(mktemp -d)"
chmod 700 "$_m02_tmp"

# _m02_faux CLE VALEUR — copie du fichier d'accès où CLE vaut VALEUR ; affiche son chemin
_m02_faux() {
  local f="$_m02_tmp/$1.env"
  (umask 077 && grep -v "^[[:space:]]*\(export \)\{0,1\}$1=" "$_m02_env" >"$f" && printf '%s="%s"\n' "$1" "$2" >>"$f")
  printf '%s' "$f"
}
# _m02_lancer FICHIER_ENV ARGS... — exécute medictl ; écrit code, stdout et stderr dans le dossier
_m02_lancer() {
  local env="$1" rc=0
  shift
  MEDICTL_ENV_FILE="$env" "$_m02_m" "$@" </dev/null >"$_m02_tmp/out" 2>"$_m02_tmp/err" || rc=$?
  echo "$rc" >"$_m02_tmp/rc"
}

# --- Journalisation : stdout = données, stderr = journal ---------------------------------
_m02_lancer "$_m02_env" -vv vm list --format json
check_cmd "-vv : stdout reste un JSON valide" jq -e 'type == "array"' "$_m02_tmp/out"
check_output "-vv : messages de niveau DEBUG sur stderr" 'DEBUG' cat "$_m02_tmp/err"
_m02_lancer "$_m02_env" vm list --format json
check_cmd "sans -v : aucun message sur stderr quand tout va bien" test ! -s "$_m02_tmp/err"

# --- Secret refusé (401) : pas de reprise, message clair --------------------------------------
_m02_lancer "$(_m02_faux PVE_TOKEN_SECRET 00000000-0000-0000-0000-000000000000)" -v vm list
check_output "jeton refusé : code 1" '^1$' cat "$_m02_tmp/rc"
check_output "jeton refusé : le message cite le 401" '401' cat "$_m02_tmp/err"
check_cmd "jeton refusé : pas de pile d'appels (Traceback)" bash -c '! grep -q Traceback "$1"' _ "$_m02_tmp/err"

# --- Proxmox injoignable : reprises avec délai, puis abandon propre ----------------------------
_m02_lancer "$(_m02_faux PVE_API_URL https://127.0.0.1:9/api2/json)" -v vm list
check_output "API injoignable : code 1" '^1$' cat "$_m02_tmp/rc"
check_cmd "API injoignable : au moins deux nouveaux essais journalisés (-v)" bash -c \
  '(($(grep -Eic "essai|tentative|retry|reprise" "$1") >= 2))' _ "$_m02_tmp/err"
check_cmd "API injoignable : pas de pile d'appels" bash -c '! grep -q Traceback "$1"' _ "$_m02_tmp/err"

# --- Certificat refusé : erreur permanente, aucune reprise ---------------------------------------
_m02_lancer "$(_m02_faux PVE_CACERT /etc/ssl/certs/ca-certificates.crt)" -v vm list
check_output "certificat refusé : code 1" '^1$' cat "$_m02_tmp/rc"
check_output "certificat refusé : le message d'erreur (dernière ligne) parle de certificat ou de TLS" \
  '[Cc]ertifica|CERTIFICA|TLS|SSL|CACERT' tail -n 1 "$_m02_tmp/err"
check_cmd "certificat refusé : aucune reprise (erreur permanente)" bash -c \
  '! grep -Eiq "essai|tentative|retry|reprise" "$1"' _ "$_m02_tmp/err"

rm -rf -- "${_m02_tmp:?}"
