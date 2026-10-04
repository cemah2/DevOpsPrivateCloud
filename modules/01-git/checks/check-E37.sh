# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E37.sh — M01-E37 « Panne : GitLab répond 502 »
# Chaîne nginx → gitlab-workhorse → puma sur git01, vue de l'extérieur et de l'intérieur.
# Lecture seule.

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E37 — Panne : GitLab répond 502"
require_cmd curl git ssh

check_http "adm01 → page de connexion de GitLab (HTTPS, certificat vérifié)" \
  "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/users/sign_in" 200
check_cmd "API GitLab joignable avec le jeton des checks" gitlab_api version
check_ssh "git01 : aucun service GitLab arrêté (gitlab-ctl status)" git01 \
  '! sudo -n gitlab-ctl status | grep -q "^down:"'
check_ssh "git01 : puma tourne depuis plus d'une minute (pas de redémarrage en boucle)" git01 \
  's=$(sudo -n gitlab-ctl status puma | sed -nE "s/^run: puma: \(pid [0-9]+\) ([0-9]+)s.*/\1/p"); [ -n "$s" ] && [ "$s" -ge 60 ]'
check_ssh_output "git01 : sonde de disponibilité /-/readiness au vert (depuis git01)" git01 '"status":"ok"' \
  "curl -s --max-time 10 --resolve $_M01_FQDN_GIT:443:127.0.0.1 https://$_M01_FQDN_GIT/-/readiness"
check_ssh "git01 : le dossier des sockets de puma appartient à git" git01 \
  '[ "$(sudo -n stat -c %U /var/opt/gitlab/gitlab-rails/sockets)" = git ]'
check_cmd "Git en SSH fonctionne aussi (git ls-remote plateforme/medisphere)" \
  env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" \
  git ls-remote --exit-code "git@$_M01_FQDN_GIT:plateforme/medisphere.git" HEAD
