# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c et regex : les $ sont évalués par le sous-shell, pas ici
#
# check-E15.sh — M04-E15 : Gestion d'erreurs : block, rescue, assert
# À lancer depuis adm01. Lecture seule : structure du rôle, documentation du contrat, et trois
# passages en --check sur dns01 avec des valeurs FAUSSES passées en -e : chacun doit être
# refusé avant toute modification (rien n'est appliqué en --check, de toute façon).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E15 — Gestion d'erreurs : block, rescue, assert"
require_cmd git jq curl

check_cmd "roles/base/meta/argument_specs.yml présent et publié sur main" \
  _m04_fichier_main roles/base/meta/argument_specs.yml
check_cmd "le contrat du rôle se lit avec ansible-doc" _m04_ans ansible-doc -t role -r roles base
check_cmd "tasks/temps.yml : un block avec un rescue" \
  bash -c 'f="$1/roles/base/tasks/temps.yml"; grep -Eq "^[[:space:]]+block:" "$f" && grep -Eq "^[[:space:]]+rescue:" "$f"' \
  _ "$_M04_SRC"
check_cmd "le retour arrière s'appuie sur une sauvegarde (backup: true)" \
  bash -c 'grep -Eq "backup:[[:space:]]*true" "$1/roles/base/tasks/temps.yml"' _ "$_M04_SRC"
check_cmd "socle-base.yml vérifie des préconditions (pre_tasks avec assert)" \
  bash -c 'f="$1/playbooks/socle-base.yml"; grep -Eq "^[[:space:]]*pre_tasks:" "$f" && grep -Eq "ansible\.builtin\.assert:" "$f"' \
  _ "$_M04_SRC"

check_cmd "refus d'une variable du mauvais type (contrat : base_chrony_client booléen)" \
  _m04o_echoue_avec 'base_chrony_client' ansible-playbook playbooks/socle-base.yml --check --limit dns01 \
  -e '{"base_chrony_client": "peut-etre"}'
check_cmd "refus d'une source de temps mal formée (assert)" \
  _m04o_echoue_avec 'base_ntp_serveurs|source' ansible-playbook playbooks/socle-base.yml --check --limit dns01 \
  -e '{"base_ntp_serveurs": ["pas une adresse"]}'
check_cmd "refus d'une adresse de connexion qui n'est pas une IP du lab (pre_tasks)" \
  _m04o_echoue_avec '10\.10\.0\.0/16|IPv4' ansible-playbook playbooks/socle-base.yml --check --limit dns01 \
  -e ansible_host=dns01.par1.medisphere.internal
_m04o_sortie="$(_m04_simuler playbooks/socle-base.yml --limit dns01)"
check_cmd "sans valeur fausse, le même passage réussit sans changement" _m04_recap "$_m04o_sortie" dns01
