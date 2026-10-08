# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E29.sh — M07-E29 « Superviser la bordure et les répartiteurs »
# À lancer depuis adm01 (où vivent le service et le timer). Lecture seule : état systemd, droits des
# fichiers, une exécution de la sonde (qui ne fait que lire), appels de la clé de supervision (qui ne
# peut que lire), règles sudo des hôtes (admin + sudo -n).

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E29 — Superviser la bordure et les répartiteurs"
require_cmd systemctl jq ssh

_m07_svc=ms-verif-reseau.service
_m07_tim=ms-verif-reseau.timer
_m07_cle="$HOME/.config/workbook/ssh-supervision-reseau"

title "Unités systemd"
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type "$_m07_svc"
check_output "le service tourne en admin" '^User=admin$' systemctl show -p User "$_m07_svc"
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' systemctl show -p OnFailure "$_m07_svc"
check_output "le service exécute la copie installée sous /usr/local" 'path=/usr/local/' systemctl show -p ExecStart "$_m07_svc"
check_cmd "le timer est activé et actif" bash -c 'systemctl is-enabled -q "$1" && systemctl is-active -q "$1"' _ "$_m07_tim"
check_output "le timer passe toutes les 5 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/5(:00)?' systemctl show -p TimersCalendar "$_m07_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' systemctl show -p Persistent "$_m07_tim"
check_cmd "le service a déjà été exécuté par systemd" bash -c \
  'v=$(systemctl show -p ExecMainStartTimestampMonotonic --value "$1" 2>/dev/null); [[ -n "$v" && "$v" != 0 ]] \
     || sudo -n journalctl -q --no-pager --since -30d -u "$1" | grep -q .' _ "$_m07_svc"
check_output "la chaîne d'alerte a été testée (alerte ms-alerte sur ce service, 30 jours)" \
  "(ÉCHEC|ECHEC) $_m07_svc" sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat

title "Accès de la supervision"
check_output "clé de supervision en 600" '^[4-7]00$' stat -c '%a' "$_m07_cle"
# _m07_force HÔTE — la clé ne donne que etat-reseau : on DEMANDE « id », on doit recevoir l'état JSON.
_m07_force() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlPath=none -i "$_m07_cle" "supervision@$1.$_M07P_ZONE" id 2>/dev/null \
    | jq -e --arg h "$1" '.hote == $h and has("adresses")' >/dev/null
}
for _m07_h in gw01 gw02 lb01 lb02; do
  check_cmd "$_m07_h : la clé de supervision n'exécute que etat-reseau (commande forcée)" _m07_force "$_m07_h"
  check_ssh "$_m07_h : sudo de « supervision » limité à etat-reseau, sans argument" "$_m07_h" '
    r=$(sudo -n cat /etc/sudoers.d/* 2>/dev/null | grep -E "^[[:space:]]*supervision[[:space:]]") || exit 1
    [ "$(grep -c . <<<"$r")" = 1 ] && grep -Eq "NOPASSWD: */usr/local/sbin/etat-reseau \"\"[[:space:]]*$" <<<"$r"'
  check_ssh "$_m07_h : clé autorisée avec restrict et from" "$_m07_h" \
    'sudo -n grep -Eq "^restrict,.*from=\"10\.10\.10\.10\".*command=" ~supervision/.ssh/authorized_keys'
done

title "La sonde, maintenant"
check_cmd "la sonde est installée, sa configuration aussi" test -x /usr/local/bin/ms-verif-reseau -a -r /usr/local/etc/ms-verif-reseau.conf
check_cmd "la sonde conclut que la bordure et les répartiteurs vont bien (code 0)" timeout 180 /usr/local/bin/ms-verif-reseau --quiet
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-reseau --nimporte-quoi >/dev/null 2>&1; echo $?'
_m07_bats() { [[ -n "$(_m07p_fichier_main plateforme/outils tests/bats/ms-verif-reseau.bats 2>/dev/null)" ]]; }
check_cmd "plateforme/outils : tests bats de ms-verif-reseau sur main" _m07_bats
