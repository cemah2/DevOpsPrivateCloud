# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E40.sh — M01-E40 « Panne : clone et push en SSH impossibles »
# Chaîne Git en SSH : configuration du client sur adm01, clé d'hôte, compte système git,
# gitlab-shell. Lecture seule.

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E40 — Panne : clone et push en SSH impossibles"
require_cmd git ssh ssh-keygen

check_cmd "adm01 : aucun rebond SSH imposé vers $_M01_FQDN_GIT" _m01_sans_rebond "$_M01_FQDN_GIT"
check_cmd "adm01 : clé d'hôte de $_M01_FQDN_GIT connue (known_hosts)" \
  bash -c 'ssh-keygen -F "$1" -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1' _ "$_M01_FQDN_GIT"
check_cmd "ssh git@$_M01_FQDN_GIT : GitLab accueille ton compte" _m01_ssh_bienvenue
check_cmd "git ls-remote en SSH sur plateforme/medisphere" \
  env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" \
  git ls-remote --exit-code "git@$_M01_FQDN_GIT:plateforme/medisphere.git" HEAD
check_ssh "git01 : compte système git sans date d'expiration dépassée" git01 \
  'e=$(sudo -n getent shadow git | cut -d: -f8); [ -z "$e" ] || [ "$e" -gt $(( $(date +%s) / 86400 )) ]'
check_ssh "git01 : gitlab-shell pointe vers une socket de Workhorse existante" git01 '
  u=$(sudo -n sed -nE "s/^gitlab_url:[[:space:]]*\"?([^\"]*)\"?.*/\1/p" /var/opt/gitlab/gitlab-shell/config.yml)
  case "$u" in
    http+unix://*) p=$(printf "%s" "${u#http+unix://}" | sed "s#%2F#/#g"); sudo -n test -S "$p" ;;
    "") exit 1 ;;
    *) exit 0 ;;
  esac'
