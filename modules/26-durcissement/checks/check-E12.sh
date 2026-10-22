# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et requêtes LogQL entre apostrophes
#
# check-E12.sh — M26-E12 : auditd et AIDE, journal d'audit dans Loki.
# À lancer depuis adm01. Lecture seule : SSH de consultation (auditctl -l et augenrules --check par
# « sudo -n »), Loki (locataire audit), GitLab, ~/m26/e12.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E12 — Tracer et détecter : auditd et AIDE"
require_cmd jq curl ssh

for _m26o_e12_h in "$(_m26o_essai deb)" "$(_m26o_essai rocky)"; do
  check_ssh "$_m26o_e12_h : auditd actif" "$_m26o_e12_h" 'systemctl is-active --quiet auditd'
  check_ssh_output "$_m26o_e12_h : règle « exec-humain » chargée dans le noyau" "$_m26o_e12_h" \
    'key=exec-humain|-k exec-humain' 'sudo -n auditctl -l'
  check_ssh_output "$_m26o_e12_h : règles chargées identiques aux fichiers de rules.d" "$_m26o_e12_h" \
    'No change' 'sudo -n augenrules --check'
  check_ssh_output "$_m26o_e12_h : journal d'audit lisible par le groupe adm (agent Alloy)" "$_m26o_e12_h" \
    '^adm$' 'stat -c %G /var/log/audit/audit.log 2>/dev/null || sudo -n stat -c %G /var/log/audit/audit.log'
  check_ssh "$_m26o_e12_h : vérification AIDE quotidienne programmée" "$_m26o_e12_h" \
    'systemctl is-enabled --quiet aide-verification.timer && systemctl is-active --quiet aide-verification.timer'
  # La métrique est réécrite à chaque vérification : plus de 2 jours = vérifications qui n'ont plus lieu.
  check_ssh "$_m26o_e12_h : métrique AIDE écrite depuis moins de 2 jours" "$_m26o_e12_h" \
    'f=$(ls /var/lib/prometheus/node-exporter/aide.prom 2>/dev/null) && t=$(awk "/^medisphere_aide_derniere_verification_secondes/ {print \$2}" "$f") && [ -n "$t" ] && [ $(( $(date +%s) - ${t%.*} )) -lt 172800 ]'
  check_cmd "Loki (audit) : événements service=\"auditd\" de $_m26o_e12_h sur 24 h" bash -c \
    '[[ "$1" -gt 0 ]]' _ "$(_m26o_loki_nb "{job=\"audit\", service=\"auditd\", host=\"$_m26o_e12_h\"}" audit 24h)"
done

check_cmd "plateforme/ansible : le rôle alloy sait envoyer des fichiers d'audit (alloy_journaux_audit)" \
  _m26o_contient "$_M26O_P_ANSIBLE" roles/alloy/templates/config.alloy.j2 'alloy_journaux_audit'
check_cmd "plateforme/ansible : /var/log/audit/audit.log déclaré pour le locataire audit" \
  bash -c 'grep -rqs "/var/log/audit/audit.log" <<<"$1"' _ \
  "$(_m26o_contenu "$_M26O_P_ANSIBLE" inventories/lab/group_vars/all/alloy_audit.yml)"
check_cmd "travail ~/m26/e12/cout.md : volume d'audit et durée d'AIDE mesurés" _m26o_travail e12/cout.md 'aide'
check_cmd "travail ~/m26/e12/requetes-logql.md : requêtes d'investigation sur le locataire audit" \
  _m26o_travail e12/requetes-logql.md 'service="auditd"'
