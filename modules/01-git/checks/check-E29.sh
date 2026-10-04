# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E29.sh — M01-E29 « Mettre à jour GitLab en suivant le chemin de montée de version »
# Lancé depuis adm01. Lecture seule (API GitLab, git01, runner01, pve01).

title "M01-E29 — Mettre à jour GitLab"
require_cmd ssh jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }

check_cmd "GitLab répond en version 19.4.x (API /version)" \
  jq -e '.version | startswith("19.4.")' <<<"$(_m01_get version)"
check_ssh_output "git01 : paquet installé en 19.4.x" git01 '^19\.4\.[0-9]+-ce\.' \
  'dpkg-query -W -f="\${Version}" gitlab-ce'
check_ssh "git01 : gitlab-ce de nouveau figé (apt-mark hold)" git01 'apt-mark showhold | grep -qx gitlab-ce'
check_ssh "git01 : aucun service GitLab arrêté" git01 \
  's=$(sudo -n gitlab-ctl status 2>&1); echo "$s" | grep -q "^run:" && ! echo "$s" | grep -q "^down:"'
check_ssh_output "git01 : migrations d'arrière-plan toutes terminées" git01 '^0$' \
  'sudo -n gitlab-psql -At -c "SELECT count(*) FROM batched_background_migrations WHERE status NOT IN (3, 6);" 2>/dev/null | tail -n 1'
check_ssh "git01 : hooks globaux toujours configurés après reconfigure (M01-E26)" git01 \
  'sudo -n grep -q "custom_hooks_dir" /var/opt/gitlab/gitaly/config.toml'
check_ssh "pve01 : aucun instantané avant-maj* laissé sur git01 (1004)" "$WB_PVE_HOST" \
  '! qm listsnapshot 1004 2>/dev/null | grep -q "avant-maj"'
check_ssh_output "runner01 : GitLab Runner aligné sur GitLab (19.4.x)" runner01 '^Version: +19\.4\.' 'gitlab-runner --version'
check_cmd "plateforme/medisphere : dernier pipeline de main réussi après la mise à jour" \
  jq -e '.[0].status == "success"' <<<"$(_m01_get "projects/plateforme%2Fmedisphere/pipelines?ref=main&per_page=1")"
check_cmd "plateforme/medisphere : runbook RB-011 dans docs/socle/runbooks/" \
  jq -e 'any(.[]?; .name | startswith("RB-011"))' \
  <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100")"
