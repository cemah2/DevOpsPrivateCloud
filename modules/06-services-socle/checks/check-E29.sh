# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c (valeurs en paramètres)
#
# check-E29.sh — M06-E29 « Superviser les services socle et l'expiration des certificats »
# À lancer depuis adm01 (où vivent le service et le timer). Lecture seule : état systemd, droits des
# fichiers, une exécution de la sonde (qui ne fait que lire), un essai d'écriture NetBox REFUSÉ.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E29 — Superviser les services socle et l'expiration des certificats"
require_cmd systemctl jq curl

_m06_svc=ms-verif-services.service
_m06_tim=ms-verif-services.timer
_m06_nbt="$HOME/.config/workbook/netbox-supervision.token"

title "Unités systemd"
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type "$_m06_svc"
check_output "le service tourne en admin" '^User=admin$' systemctl show -p User "$_m06_svc"
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure "$_m06_svc"
check_output "le service exécute la copie installée sous /usr/local" 'path=/usr/local/' \
  systemctl show -p ExecStart "$_m06_svc"
check_cmd "le timer est activé" systemctl is-enabled --quiet "$_m06_tim"
check_cmd "le timer est actif" systemctl is-active --quiet "$_m06_tim"
check_output "le timer passe toutes les 15 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/15(:00)?' \
  systemctl show -p TimersCalendar "$_m06_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' \
  systemctl show -p Persistent "$_m06_tim"
check_cmd "le service a déjà été exécuté par systemd" bash -c \
  'v=$(systemctl show -p ExecMainStartTimestampMonotonic --value "$1" 2>/dev/null); [[ -n "$v" && "$v" != 0 ]] \
     || sudo -n journalctl -q --no-pager --since -30d -u "$1" | grep -q .' _ "$_m06_svc"
check_output "la chaîne d'alerte a été testée (alerte ms-alerte sur ce service, 30 jours)" \
  "(ÉCHEC|ECHEC) $_m06_svc" sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat

title "Identités de supervision"
check_output "jeton NetBox de supervision en 600" '^[4-7]00$' stat -c '%a' "$_m06_nbt"
check_output "identité Kea de supervision en 600" '^[4-7]00$' stat -c '%a' "$_M06P_KEA_ENV"
# Essai d'écriture SANS effet possible : création d'une étiquette au nom invalide (refusée par la
# validation de NetBox même pour un jeton autorisé) ; un jeton en lecture est refusé AVANT (403).
check_output "le jeton NetBox de supervision ne peut pas écrire (403)" '^403$' bash -c \
  'curl -s -o /dev/null -w "%{http_code}" --max-time "$2" --cacert "$3" -K - -X POST -H "Content-Type: application/json" \
     --data "{\"name\": \"\", \"slug\": \"\"}" "$1/api/extras/tags/" <<<"header = \"Authorization: Bearer $(cat "$4")\""' \
  _ "${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}" "$WB_TIMEOUT" "$_M06P_RACINE" "$_m06_nbt"

title "La sonde, maintenant"
check_cmd "la sonde est installée et ne contient aucun secret évident" bash -c \
  'test -x /usr/local/bin/ms-verif-services && ! grep -Eq "nbt_[A-Za-z0-9]{8}|KEA_API_PASSWORD=[^\"$]" /usr/local/bin/ms-verif-services'
check_cmd "la configuration de la sonde est installée" test -r /usr/local/etc/ms-verif-services.conf
check_cmd "la sonde conclut que les services socle vont bien (code 0)" \
  timeout 180 /usr/local/bin/ms-verif-services --quiet
check_output "un seuil de certificats absurde (400 jours) la fait échouer (code 1)" '^1$' \
  bash -c 'timeout 180 /usr/local/bin/ms-verif-services --quiet --seuil-certificats 400 >/dev/null 2>&1; echo $?'
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-services --nimporte-quoi >/dev/null 2>&1; echo $?'
check_cmd "plateforme/outils : tests bats de ms-verif-services sur main" \
  _m06p_fichier_existe plateforme/outils tests/bats/ms-verif-services.bats
