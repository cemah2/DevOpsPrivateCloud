# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL, filtres jq et commandes distantes entre apostrophes
#
# check-E11.sh — M21-E11 : Sondes blackbox et supervision hors cluster sur mon01
# À lancer depuis adm01. Lecture seule : SSH vers mon01 (systemctl, ss), API du Prometheus et de
# l'Alertmanager témoins (GET), Mailpit (mailpit_api), GitLab (fichiers sur main).

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E11 — Sondes blackbox et supervision hors cluster sur mon01"
require_cmd jq curl ssh

check_ssh "mon01 : prometheus, alertmanager et blackbox_exporter actifs" "$_M21O_MON01" \
  'systemctl is-active --quiet prometheus alertmanager blackbox_exporter'
check_ssh_output "mon01 : chaque service tourne sous son utilisateur dédié" "$_M21O_MON01" \
  '^prometheus alertmanager blackbox$' \
  'echo $(systemctl show -p User --value prometheus) $(systemctl show -p User --value alertmanager) $(systemctl show -p User --value blackbox_exporter)'
check_ssh_output "mon01 : blackbox_exporter n'écoute que sur 127.0.0.1:9115" "$_M21O_MON01" \
  '^127\.0\.0\.1:9115$' 'ss -Htln "sport = :9115" | awk "{print \$4}" | sort -u'

check_output "Prometheus témoin en 3.13 (LTS)" '"version":"3\.13\.' _m21o_temoin "status/buildinfo"
check_output "Alertmanager témoin en 0.34" '"version":"0\.34\.' \
  curl -sf --max-time "$WB_TIMEOUT" "$_M21O_TEMOIN_AM/api/v2/status"

for _m21o_e11_m in https_2xx:6 icmp:5 dns_soa:2 smtp_starttls:1; do
  check_cmd "témoin : au moins ${_m21o_e11_m##*:} sonde(s) ${_m21o_e11_m%%:*} dans le job blackbox" \
    _m21o_temoin_au_moins "count(probe_success{job=\"blackbox\", module=\"${_m21o_e11_m%%:*}\"})" "${_m21o_e11_m##*:}"
done
check_cmd "témoin : toutes les sondes réussissent (aucune probe_success à 0, cible de test retirée)" \
  _m21o_temoin_vide 'probe_success{job="blackbox"} == 0'
check_cmd "témoin : règles chargées, aucune en erreur, au moins trois alertes" _m21o_json "$(_m21o_temoin "rules")" '
  ([.data.groups[].rules[] | select(.type == "alerting")] | length) >= 3
  and ([.data.groups[].rules[] | select(.health == "err")] | length) == 0'
check_output "Alertmanager témoin : récepteur vers astreinte@medisphere.internal" 'astreinte@medisphere\.internal' \
  curl -sf --max-time "$WB_TIMEOUT" "$_M21O_TEMOIN_AM/api/v2/status"
check_output "Mailpit : au moins un courriel de l'Alertmanager témoin" '"messages_count": *[1-9]' \
  mailpit_api "search?query=$(_m21o_uri 'subject:"[témoin mon01]"')"
check_cmd "plateforme/ansible : rôle supervision_temoin sur main" \
  _m21o_fichier "$_M21O_P_ANSIBLE" roles/supervision_temoin/tasks/main.yml
check_cmd "plateforme/ansible : playbook supervision-temoin.yml sur main" \
  _m21o_fichier "$_M21O_P_ANSIBLE" playbooks/supervision-temoin.yml
