# shellcheck shell=bash
# check-E35.sh — M02-E35 « Panne : le script marche à la main mais pas la nuit » : état sain.
# Le contrôle planifié des sauvegardes (M02-E26) s'exécute sous systemd dans un environnement
# compatible avec le script, et son dernier passage a réussi. Lecture seule, sur adm01.

title "M02-E35 — Le contrôle planifié tourne comme à la main"
require_cmd systemctl git

_m02_e35_svc=ms-verif-sauvegardes.service
_m02_e35_outils="${WB_SRC:-$HOME/src}/outils"
_m02_e35_cfg="$HOME/.config/workbook"

_m02_e35_prop() { systemctl show "$_m02_e35_svc" -p "$1" --value 2>/dev/null; }

# Le service n'est pas privé du dossier personnel de admin (où vivent secrets et clone).
_m02_e35_home_visible() {
  [[ "$(_m02_e35_prop ProtectHome)" != yes ]]
}

# _m02_e35_exempte HÔTE LISTE_NO_PROXY — l'hôte figure dans la liste (nom exact, suffixe de
# domaine « .exemple », « * », ou réseau IPv4 en notation CIDR).
_m02_e35_exempte() {
  local h="$1" e ip res masque a b c d
  local -a liste
  IFS=, read -r -a liste <<<"$2"
  for e in "${liste[@]}"; do
    e="${e// /}"
    [[ -n "$e" ]] || continue
    [[ "$e" == "*" || "$e" == "$h" ]] && return 0
    [[ "$e" == .* && "$h" == *"$e" ]] && return 0
    [[ "$h" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [[ "$e" =~ ^([0-9.]+)/([0-9]{1,2})$ ]]; then
      masque="${BASH_REMATCH[2]}"
      IFS=. read -r a b c d <<<"${BASH_REMATCH[1]}"; res=$(((a << 24) | (b << 16) | (c << 8) | d))
      IFS=. read -r a b c d <<<"$h"; ip=$(((a << 24) | (b << 16) | (c << 8) | d))
      ((masque == 0 || (ip >> (32 - masque)) == (res >> (32 - masque)))) && return 0
    fi
  done
  return 1
}

# _m02_e35_hote FICHIER VARIABLE — hôte de l'URL lue dans un fichier d'accès (sans l'exécuter
# dans le shell du contrôle : sous-shell).
_m02_e35_hote() {
  # shellcheck source=/dev/null
  (source "$1" 2>/dev/null && printf '%s' "${!2:-}") | sed -E 's#^https?://\[?([^]/:]+).*#\1#'
}

# Si un proxy est imposé au service, les API de Proxmox VE et de PBS en sont exemptées.
_m02_e35_proxy_ok() {
  local env np h
  env="$(_m02_e35_prop Environment)"
  grep -Eqi '(^| )https?_proxy=' <<<"$env" || return 0
  np="$(grep -Eio '(^| )no_proxy=[^ ]*' <<<"$env" | tail -n 1 | cut -d= -f2-)"
  for h in "$(_m02_e35_hote "$_m02_e35_cfg/pve-lecture.env" PVE_API_URL)" \
    "$(_m02_e35_hote "$_m02_e35_cfg/pbs-lecture.env" PBS_API_URL)"; do
    [[ -n "$h" ]] || return 1
    _m02_e35_exempte "$h" "$np" || return 1
  done
}

# Le service lance la copie installée (/usr/local/bin, M02-E26), identique à la version du
# script sur la branche main du clone.
_m02_e35_meme_script() {
  local p
  p="$(_m02_e35_prop ExecStart | sed -nE 's/.*path=([^ ;]+).*/\1/p' | head -n 1)"
  [[ "$p" == /usr/local/bin/ms-verif-sauvegardes ]] || return 1
  cmp -s "$p" <(git -C "$_m02_e35_outils" show main:bin/ms-verif-sauvegardes 2>/dev/null)
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
check_cmd "aucun proxy n'intercepte les appels du service aux API Proxmox VE et PBS" _m02_e35_proxy_ok
check_cmd "le service exécute la copie installée du script (/usr/local/bin), identique à main" _m02_e35_meme_script
check_cmd "dernier passage du service réussi, il y a moins de 26 h" _m02_e35_dernier_ok
check_cmd "le timer ms-verif-sauvegardes est actif" systemctl is-active -q ms-verif-sauvegardes.timer
