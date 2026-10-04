# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E38.sh — M01-E38 « Panne : le runner ne prend plus les jobs »
# Côté runner01 (service, résolution, TLS) et côté GitLab (réglages du runner, dernier contact).
# Lecture seule : le jeton du runner n'est jamais lu ni rejoué ; on constate qu'il est accepté
# par la date de dernier contact que GitLab enregistre à chaque demande de jobs authentifiée
# (contacted_at, toutes les ~3 s pour un runner sain). Les réglages du runner se lisent par
# l'API d'administration (jeton des checks + admin_mode une fois l'Admin Mode activé, M01-E31).

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
  # Un jeton refusé (403) ou une forge injoignable n'actualisent plus contacted_at. Seuil de
  # 180 s : marge pour l'interrogation longue de Workhorse (jusqu'à 60 s si elle est activée).
  check_cmd "runner $_m01_rid : a contacté GitLab avec un jeton valide il y a moins de 3 min" \
    _m01_api_ok "runners/$_m01_rid" \
    '(.contacted_at // "") | length > 0 and (now - (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601)) < 180'
else
  skip "réglages du runner dans GitLab" "runner du socle non identifié"
fi
