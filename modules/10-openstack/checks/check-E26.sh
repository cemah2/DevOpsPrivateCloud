# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E26.sh — M10-E26 « Superviser OpenStack »
# À lancer depuis adm01 (où vivent le service et le timer). Lecture seule : état systemd, droits
# des fichiers, une exécution de la sonde (qui ne fait que lire), règles d'accès de Keystone.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E26 — Superviser OpenStack"
require_cmd systemctl openstack jq

_m10_svc=ms-verif-openstack.service
_m10_tim=ms-verif-openstack.timer

title "Unités systemd"
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type "$_m10_svc"
check_output "le service tourne en admin" '^User=admin$' systemctl show -p User "$_m10_svc"
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure "$_m10_svc"
check_output "le service exécute la copie installée sous /usr/local" 'path=/usr/local/' \
  systemctl show -p ExecStart "$_m10_svc"
check_cmd "le timer est activé et actif" bash -c 'systemctl is-enabled --quiet "$1" && systemctl is-active --quiet "$1"' _ "$_m10_tim"
check_output "le timer passe toutes les 15 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/15(:00)?' \
  systemctl show -p TimersCalendar "$_m10_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' \
  systemctl show -p Persistent "$_m10_tim"
check_cmd "le service a déjà été exécuté par systemd" bash -c \
  'v=$(systemctl show -p ExecMainStartTimestampMonotonic --value "$1" 2>/dev/null); [[ -n "$v" && "$v" != 0 ]]' _ "$_m10_svc"
check_output "la chaîne d'alerte a été testée (alerte ms-alerte sur ce service, 30 jours)" \
  "(ÉCHEC|ECHEC) $_m10_svc" sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat

title "Identité de la sonde"
check_output "secure.yaml (~/.config/openstack) en 600" '^[4-7]00$' stat -c '%a' "$HOME/.config/openstack/secure.yaml"
check_cmd "clouds.yaml : cloud medisphere-supervision par application credential" bash -c \
  'grep -A3 "medisphere-supervision:" "$HOME/.config/openstack/clouds.yaml" | grep -q "v3applicationcredential"'
_m10_regles_get() {
  local r
  r="$(_m10p_os access rule list --user svc-supervision --user-domain Default)" || return 1
  jq -e 'type == "array" and length > 0 and all(.[]; (.Method // .method) == "GET")' >/dev/null <<<"$r"
}
check_cmd "règles d'accès de svc-supervision : présentes, et GET seulement" _m10_regles_get
check_cmd "le cloud medisphere-supervision obtient un jeton" \
  timeout 60 openstack --os-cloud medisphere-supervision token issue -f value -c expires

title "La sonde, maintenant"
check_cmd "la sonde et sa configuration sont installées" \
  bash -c 'test -x /usr/local/bin/ms-verif-openstack && test -r /usr/local/etc/ms-verif-openstack.conf'
check_cmd "la sonde conclut que le cloud va bien (code 0)" timeout 300 /usr/local/bin/ms-verif-openstack --quiet
check_output "un seuil de certificats absurde (400 jours) la fait échouer (code 1)" '^1$' \
  bash -c 'timeout 300 /usr/local/bin/ms-verif-openstack --quiet --seuil-certificats 400 >/dev/null 2>&1; echo $?'
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-openstack --nimporte-quoi >/dev/null 2>&1; echo $?'
check_cmd "plateforme/outils : tests bats de ms-verif-openstack sur main" \
  _m10p_fichier_existe plateforme/outils tests/bats/ms-verif-openstack.bats
check_cmd "plateforme/outils : dernier pipeline de main réussi" _m10p_pipeline_ok plateforme/outils
check_cmd "plateforme/outils : guide d'astreinte complété pour OpenStack" \
  _m10p_fichier_contient plateforme/outils docs/astreinte.md 'ms-verif-openstack|openstack'
