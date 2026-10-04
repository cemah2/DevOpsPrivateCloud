# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E38.sh — M01-E38 « Panne : le runner ne prend plus les jobs »
# Côté runner01 (service, résolution, TLS, jeton) et côté GitLab (réglages du runner).
# Lecture seule : la vérification du jeton utilise POST /runners/verify, qui ne modifie rien
# d'autre que la date de dernier contact du runner (ce que fait le runner toutes les 3 s).

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E38 — Panne : le runner ne prend plus les jobs"
require_cmd jq curl

check_ssh "runner01 : service gitlab-runner actif et activé au démarrage" runner01 \
  'systemctl is-active -q gitlab-runner && systemctl is-enabled -q gitlab-runner'
check_ssh "runner01 : git01.par1.medisphere.internal résout vers 10.10.20.12" runner01 \
  "getent ahostsv4 $_M01_FQDN_GIT | awk '{print \$1}' | sort -u | grep -qx '10\.10\.20\.12'"
check_ssh "runner01 : GitLab joignable en HTTPS, certificat vérifié" runner01 \
  "curl -sf -o /dev/null --max-time 10 https://$_M01_FQDN_GIT/users/sign_in"
check_ssh "runner01 : le jeton du runner est accepté par GitLab" runner01 '
  t=$(sudo -n awk -F"\"" "/^[[:space:]]*token[[:space:]]*=/ {print \$2; exit}" /etc/gitlab-runner/config.toml)
  s=$(sudo -n cat /etc/gitlab-runner/.runner_system_id 2>/dev/null || true)
  [ -n "$t" ] || exit 1
  printf "token=%s&system_id=%s" "$t" "$s" | curl -sf -o /dev/null --max-time 10 -X POST --data @- \
    https://git01.par1.medisphere.internal/api/v4/runners/verify'

_m01_rid="$(gitlab_api 'runners/all?type=instance_type&tag_list=shell,socle&per_page=100' 2>/dev/null \
  | jq -r 'if length == 1 then .[0].id else empty end' 2>/dev/null)" || _m01_rid=""
check_cmd "GitLab : exactement un runner d'instance étiqueté shell et socle" test -n "$_m01_rid"
if [[ -n "$_m01_rid" ]]; then
  check_cmd "runner $_m01_rid : en ligne et actif (non mis en pause)" \
    _m01_api_ok "runners/$_m01_rid" '.status == "online" and .paused == false'
  check_cmd "runner $_m01_rid : prend aussi les jobs des branches non protégées" \
    _m01_api_ok "runners/$_m01_rid" '.access_level == "not_protected"'
  check_cmd "runner $_m01_rid : ne prend pas les jobs sans étiquette" \
    _m01_api_ok "runners/$_m01_rid" '.run_untagged == false'
else
  skip "réglages du runner dans GitLab" "runner du socle non identifié"
fi
