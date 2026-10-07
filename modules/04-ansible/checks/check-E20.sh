# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c et regex : les $ sont évalués par le sous-shell, pas ici
#
# check-E20.sh — M04-E20 : ansible-lint en pre-commit et en CI
# À lancer depuis adm01. Lecture seule : configuration, hook local, ansible-lint lancé dans la
# copie de travail (une minute environ), dernier pipeline de main (API GitLab).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E20 — ansible-lint en pre-commit et en CI"
require_cmd git jq curl

check_cmd ".ansible-lint publié sur main" _m04_fichier_main .ansible-lint
check_cmd ".ansible-lint : profil production" _m04_contient .ansible-lint '^profile:[[:space:]]*production'
check_cmd ".ansible-lint : aucune règle désactivée pour tout le projet" \
  bash -c '! grep -Eq "^skip_list:[[:space:]]*$" "$1/.ansible-lint" || ! grep -Eq "^[[:space:]]+-[[:space:]]+[a-z]" <(sed -n "/^skip_list:/,/^[a-z]/p" "$1/.ansible-lint")' \
  _ "$_M04_SRC"
check_cmd ".pre-commit-config.yaml : hook ansible-lint" _m04_contient .pre-commit-config.yaml 'id:[[:space:]]*ansible-lint'
check_cmd "hooks pre-commit installés dans la copie de travail" test -x "$_M04_SRC/.git/hooks/pre-commit"
check_cmd ".gitlab-ci.yml : job ansible-lint" _m04_contient .gitlab-ci.yml '^ansible-lint:'
check_cmd "ansible-lint passe sur la copie de travail (profil production)" _m04_ans ansible-lint -q
check_output "dernier pipeline de main : job ansible-lint réussi" '^success$' _m04o_dernier_job_main ansible-lint
