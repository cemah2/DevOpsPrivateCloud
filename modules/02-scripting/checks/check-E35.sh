# shellcheck shell=bash
# check-E35.sh — M02-E35 « Panne : le script marche à la main mais pas la nuit » : état sain.
# Le contrôle planifié des sauvegardes (M02-E26) s'exécute sous systemd dans un environnement
# compatible avec le script, et son dernier passage a réussi. Lecture seule, sur adm01.

title "M02-E35 — Le contrôle planifié tourne comme à la main"
require_cmd systemctl

_m02_e35_svc=ms-verif-sauvegardes.service
_m02_e35_outils="${WB_SRC:-$HOME/src}/outils"

_m02_e35_prop() { systemctl show "$_m02_e35_svc" -p "$1" --value 2>/dev/null; }

# Le service n'est pas privé du dossier personnel de admin (où vivent secrets et clone).
_m02_e35_home_visible() {
  [[ "$(_m02_e35_prop ProtectHome)" != yes ]]
}

# Si un proxy est imposé au service, l'adresse de l'API Proxmox en est exemptée.
_m02_e35_proxy_ok() {
  local env np hote
  env="$(_m02_e35_prop Environment)"
  grep -Eqi '(^| )https?_proxy=' <<<"$env" || return 0
  # shellcheck source=/dev/null
  hote="$(source "$HOME/.config/workbook/pve-api.env" && printf '%s' "$PVE_API_URL" \
    | sed -E 's#^https?://\[?([^]/:]+).*#\1#')"
  np="$(grep -Eio '(^| )no_proxy=[^ ]*' <<<"$env" | tail -n 1 | cut -d= -f2-)"
  [[ -n "$hote" && ",$np," == *",$hote,"* ]]
}

# Le programme lancé par le service est celui du dépôt (lien ou copie identique).
_m02_e35_meme_script() {
  local p
  p="$(_m02_e35_prop ExecStart | sed -nE 's/.*path=([^ ;]+).*/\1/p' | head -n 1)"
  [[ -n "$p" && -f "$_m02_e35_outils/bin/ms-verif-sauvegardes" ]] || return 1
  [[ "$(readlink -f "$p")" == "$(readlink -f "$_m02_e35_outils/bin/ms-verif-sauvegardes")" ]] \
    || cmp -s "$p" "$_m02_e35_outils/bin/ms-verif-sauvegardes"
}

# Dernier passage réussi, il y a moins de 26 heures.
_m02_e35_dernier_ok() {
  local fin
  [[ "$(_m02_e35_prop Result)" == success && "$(_m02_e35_prop ExecMainStatus)" == 0 ]] || return 1
  fin="$(systemctl show "$_m02_e35_svc" -p ExecMainExitTimestamp --value --timestamp=unix 2>/dev/null)"
  fin="${fin#@}"
  [[ "$fin" =~ ^[0-9]+$ ]] && (($(date +%s) - fin < 26 * 3600))
}

check_cmd "unité $_m02_e35_svc présente" systemctl cat "$_m02_e35_svc"
check_output "le service s'exécute sous le compte admin" '^admin$' _m02_e35_prop User
check_cmd "le service a accès au dossier personnel de admin (secrets, clone)" _m02_e35_home_visible
check_cmd "aucun proxy n'intercepte les appels du service à l'API Proxmox" _m02_e35_proxy_ok
check_cmd "le service exécute la version du script présente dans le dépôt" _m02_e35_meme_script
check_cmd "dernier passage du service réussi, il y a moins de 26 h" _m02_e35_dernier_ok
check_cmd "le timer ms-verif-sauvegardes est actif" systemctl is-active -q ms-verif-sauvegardes.timer
