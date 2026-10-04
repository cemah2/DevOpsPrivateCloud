# shellcheck shell=bash
# shellcheck disable=SC2016  # le code entre apostrophes est évalué dans un bash neuf
#
# check-E10.sh — M02-E10 : bibliothèque Bash commune lib/ms-commun.sh
# À lancer depuis adm01. Lecture seule : la bibliothèque est chargée dans des shells
# jetables ; ses seuls appels à l'API Proxmox sont des lectures (GET).

title "M02-E10 — Bibliothèque Bash commune lib/ms-commun.sh"
require_cmd bash jq curl shellcheck git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_lib="$_m02_r/lib/ms-commun.sh"
_m02_env="${MS_PVE_ENV_FILE:-$HOME/.config/workbook/pve-api.env}"

# _m02_lib_code ATTENDU CODE — vrai si CODE, exécuté après chargement de la bibliothèque
# dans un bash neuf en mode strict (entrée standard hors terminal), sort avec le code ATTENDU.
_m02_lib_code() {
  local attendu="$1" rc=0
  bash -c 'set -euo pipefail; MS_PROG=check-e10; source "$1"; eval "$2"' _ "$_m02_lib" "$2" \
    </dev/null >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq "$attendu" ]]
}
# _m02_lib_sortie CODE — stdout et stderr de CODE exécuté après chargement de la bibliothèque
_m02_lib_sortie() {
  bash -c 'set -euo pipefail; MS_PROG=check-e10; source "$1"; eval "$2"' _ "$_m02_lib" "$1" </dev/null 2>&1
}

# --- Le fichier --------------------------------------------------------------------
check_cmd "lib/ms-commun.sh présente dans ~/src/outils" test -f "$_m02_lib"
check_cmd "la bibliothèque passe ShellCheck" bash -c 'cd "$1" && shellcheck -x lib/ms-commun.sh' _ "$_m02_r"
check_cmd "la bibliothèque est fusionnée dans main (GitLab)" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/lib%2Fms-commun.sh?ref=main"
check_cmd "exécutée au lieu d'être chargée, elle refuse (code non nul)" \
  bash -c '! bash "$1" </dev/null >/dev/null 2>&1' _ "$_m02_lib"
check_cmd "la bibliothèque ne change pas les options du shell qui la charge" \
  bash -c 'set +euo pipefail; source "$1" >/dev/null 2>&1; [[ $- != *e* && $- != *u* ]]' _ "$_m02_lib"

# --- Journalisation et sortie ----------------------------------------------------------------
check_output "log_info : horodatage ISO 8601, nom du script, message (sur stderr)" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}.*check-e10.*message-e10' \
  _m02_lib_sortie 'log_info message-e10 2>&1 >/dev/null'
check_cmd "log_info, log_warn, log_err n'écrivent rien sur stdout" \
  _m02_lib_code 0 '[[ -z "$(log_info a 2>/dev/null; log_warn b 2>/dev/null; log_err c 2>/dev/null)" ]]'
check_cmd "die sort avec le code 1 par défaut" _m02_lib_code 1 'die "fin"'
check_cmd "die transmet le code demandé (3)" _m02_lib_code 3 'die "refus" 3'
check_cmd "require_cmd échoue si une commande manque" \
  _m02_lib_code 1 'require_cmd commande-inexistante-e10'
check_cmd "require_cmd réussit si tout est présent" _m02_lib_code 0 'require_cmd bash jq curl'

# --- confirm et retry -----------------------------------------------------------------------
check_cmd "confirm refuse sans terminal" _m02_lib_code 0 '! confirm "Supprimer ?"'
check_cmd "confirm accepte sans terminal avec MS_YES=1" _m02_lib_code 0 'MS_YES=1 confirm "Supprimer ?"'
check_cmd "retry fait exactement N tentatives avant d'abandonner" _m02_lib_code 0 \
  'n=0; essai() { n=$((n + 1)); return 1; }; retry 3 0 essai || true; [[ $n -eq 3 ]]'
check_cmd "retry s'arrête dès que la commande réussit" _m02_lib_code 0 \
  'n=0; essai() { n=$((n + 1)); [[ $n -ge 2 ]]; }; retry 5 0 essai && [[ $n -eq 2 ]]'
check_cmd "retry renvoie un code non nul après le dernier échec" _m02_lib_code 0 '! retry 2 0 false'

# --- pve_api (lectures seulement) -----------------------------------------------------------
check_cmd "fichier d'accès à l'API présent ($_m02_env)" test -r "$_m02_env"
check_cmd "pve_api GET /version renvoie le champ data (JSON avec .version)" \
  _m02_lib_code 0 'pve_api GET /version | jq -e .version'
check_output "pve_api : un refus de l'API est signalé avec son code HTTP (403)" '403' \
  _m02_lib_sortie '. "$HOME/.config/workbook/pve-api.env"; pve_api GET "/nodes/$PVE_NODE/syslog" >/dev/null || true'
check_cmd "pve_api : un refus de l'API donne un code de retour non nul" \
  _m02_lib_code 0 '. "$HOME/.config/workbook/pve-api.env"; ! pve_api GET "/nodes/$PVE_NODE/syslog" >/dev/null'

# Fichier d'accès lisible par tous : la bibliothèque doit refuser de s'en servir.
_m02_tmp="$(mktemp -d)"
if [[ -r "$_m02_env" ]]; then
  install -m 644 "$_m02_env" "$_m02_tmp/pve-api-644.env"
fi
check_cmd "pve_api refuse un fichier d'accès lisible par les autres (mode 644)" \
  _m02_lib_code 0 "MS_PVE_ENV_FILE='$_m02_tmp/pve-api-644.env'; ! pve_api GET /version"

# Faux curl qui note ses arguments : le secret ne doit jamais y figurer (il serait visible dans ps).
cat >"$_m02_tmp/curl" <<'FIN'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${0%/*}/arguments"
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"data":{"version":"9"}}\n'
FIN
chmod 700 "$_m02_tmp/curl"
check_cmd "le secret du jeton n'apparaît jamais dans les arguments de curl" bash -c '
  PATH="$1:$PATH" bash -c "source \"\$1\"; pve_api GET /version" _ "$2" </dev/null >/dev/null 2>&1 || true
  [[ -s "$1/arguments" ]] || exit 1
  secret="$(. "$3" >/dev/null 2>&1; printf "%s" "${PVE_TOKEN_SECRET:-}")"
  [[ -n "$secret" ]] && ! grep -qF -f <(printf "%s\n" "$secret") "$1/arguments"' _ "$_m02_tmp" "$_m02_lib" "$_m02_env"
rm -rf -- "${_m02_tmp:?}"
