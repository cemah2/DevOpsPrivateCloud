# shellcheck shell=bash
# check-E41.sh — M02-E41 « Panne : le contrôle planifié ne tourne plus » : état sain.
# Timer chargé, actif, activé au démarrage, déclenché chaque jour à 07:30, prochaine échéance
# dans moins de 25 h ; le dernier passage du service a réellement exécuté le contrôle (pas
# sauté par une condition) et a réussi. Lecture seule (systemctl show), sur adm01.

title "M02-E41 — Le contrôle planifié des sauvegardes tourne"
require_cmd systemctl

_m02_e41_t=ms-verif-sauvegardes.timer
_m02_e41_s=ms-verif-sauvegardes.service

_m02_e41_ts() { # _m02_e41_ts UNITÉ PROPRIÉTÉ — horodatage en secondes depuis l'époque
  local v
  v="$(systemctl show "$1" -p "$2" --value --timestamp=unix 2>/dev/null)"
  v="${v#@}"
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v"
}

_m02_e41_prochaine() {
  local n
  n="$(_m02_e41_ts "$_m02_e41_t" NextElapseUSecRealtime)" || return 1
  ((n > $(date +%s) && n - $(date +%s) < 25 * 3600))
}

_m02_e41_dernier() {
  local fin
  [[ "$(systemctl show "$_m02_e41_s" -p ConditionResult --value)" == yes ]] || return 1
  [[ "$(systemctl show "$_m02_e41_s" -p Result --value)" == success ]] || return 1
  fin="$(_m02_e41_ts "$_m02_e41_s" ExecMainExitTimestamp)" || return 1
  (($(date +%s) - fin < 26 * 3600))
}

check_output "timer : unité chargée sans erreur de configuration" '^loaded$' \
  systemctl show "$_m02_e41_t" -p LoadState --value
check_cmd "timer : actif" systemctl is-active -q "$_m02_e41_t"
check_cmd "timer : activé au démarrage de adm01" systemctl is-enabled -q "$_m02_e41_t"
check_output "timer : déclenchement quotidien à 07:30" 'OnCalendar=\*-\*-\* 07:30:00' \
  systemctl show "$_m02_e41_t" -p TimersCalendar --value
check_cmd "timer : prochaine exécution dans moins de 25 h" _m02_e41_prochaine
check_cmd "service : dernier passage exécuté (non sauté), réussi, il y a moins de 26 h" _m02_e41_dernier
# Résultat du dernier passage gardé en mémoire par systemd seulement : perdu au redémarrage.
if [[ "$(systemctl show "$_m02_e41_s" -p ExecMainStartTimestampMonotonic --value 2>/dev/null)" == 0 ]]; then
  printf '         (aucun passage depuis le démarrage de adm01 : sudo systemctl start %s, puis relance)\n' "$_m02_e41_s"
fi
