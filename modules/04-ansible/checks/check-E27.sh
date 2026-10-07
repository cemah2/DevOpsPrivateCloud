# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E27.sh — M04-E27 « Chaîne CI Ansible : lint, Molecule, --check en MR, application contrôlée »
# Pipeline sur main, variables protégées, branches protégées, déploiement lab/socle réussi,
# check-socle en MR, flux runner01 → gw01/adm01, clé ansible-ci restreinte, clés d'hôte
# connues de runner01, documentation.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E27 — Chaîne CI Ansible"
require_cmd jq ssh curl

title "Pipeline (branche main)"
check_cmd ".gitlab-ci.yml : job ansible-lint" _m04_fichier_main_contient .gitlab-ci.yml '^ansible-lint:'
check_cmd ".gitlab-ci.yml : jobs Molecule" _m04_fichier_main_contient .gitlab-ci.yml 'molecule test'
check_cmd ".gitlab-ci.yml : aperçu --check --diff (check-socle)" _m04_fichier_main_contient .gitlab-ci.yml '^check-socle:'
check_cmd ".gitlab-ci.yml : job appliquer" _m04_fichier_main_contient .gitlab-ci.yml '^appliquer:'
check_cmd ".gitlab-ci.yml : environnement lab/socle" _m04_fichier_main_contient .gitlab-ci.yml 'name:[[:space:]]*lab/socle'
check_cmd ".gitlab-ci.yml : application manuelle" _m04_fichier_main_contient .gitlab-ci.yml 'when:[[:space:]]*manual'
check_cmd ".gitlab-ci.yml : une seule application à la fois (resource_group)" _m04_fichier_main_contient .gitlab-ci.yml 'resource_group:'
check_cmd ".gitlab-ci.yml : ménage des instances Molecule orphelines" _m04_fichier_main_contient .gitlab-ci.yml 'menage'
check_cmd "inventaire : adm01 n'est plus en connexion locale inconditionnelle" \
  _m04_fichier_main_sans inventories/lab/host_vars/adm01/main.yml '^ansible_connection:[[:space:]]*"?local"?[[:space:]]*$'

title "Secrets et protections (GitLab)"
check_cmd "ANSIBLE_CI_SSH_KEY : variable de type fichier, protégée" \
  _m04_variable_ok ANSIBLE_CI_SSH_KEY '.protected and .variable_type == "file"'
check_cmd "VAULT_PASS_LAB : variable de type fichier, protégée" \
  _m04_variable_ok VAULT_PASS_LAB '.protected and .variable_type == "file"'
check_cmd "PROXMOX_TOKEN_SECRET : protégée et masquée" \
  _m04_variable_ok PROXMOX_TOKEN_SECRET '.protected and (.masked or (.masked_and_hidden // false))'
check_cmd "branche main protégée" _m04_api_ok "$_M04_PROJET/protected_branches" 'any(.[]; .name == "main")'
check_cmd "motif conf/* protégé" _m04_api_ok "$_M04_PROJET/protected_branches" 'any(.[]; .name == "conf/*")'

title "Exécutions"
check_cmd "environnement lab/socle : un déploiement réussi" \
  _m04_api_ok "$_M04_PROJET/deployments?environment=lab%2Fsocle&status=success&per_page=1" 'length > 0'
check_cmd "un pipeline de MR a exécuté check-socle avec succès" \
  _m04_job_dans_pipelines "source=merge_request_event&per_page=20" '^check-socle$' '["success"]'
check_cmd "un job Molecule a réussi en CI" _m04_job_reussi '^molecule:'

title "Accès de runner01 au socle"
for _m04_cible in 10.10.10.1 10.10.10.10; do
  check_ssh "runner01 → $_m04_cible : SSH (TCP 22) joignable" runner01 \
    "timeout 5 bash -c 'exec 3<>/dev/tcp/$_m04_cible/22'"
  check_ssh "runner01 connaît la clé d'hôte de $_m04_cible" runner01 \
    "ssh-keygen -F $_m04_cible -f /etc/ssh/ssh_known_hosts >/dev/null 2>&1 || sudo -n -u gitlab-runner sh -c 'ssh-keygen -F $_m04_cible -f \$HOME/.ssh/known_hosts' >/dev/null 2>&1"
done
check_ssh_output "gw01 : chaîne input, SSH depuis runner01" gw01 '10\.10\.20\.15[^#]*dport 22' \
  "sudo -n nft list chain inet filter input"
check_ssh_output "gw01 : chaîne forward, runner01 → adm01 SSH" gw01 '10\.10\.20\.15[^#]*10\.10\.10\.10[^#]*dport 22|10\.10\.10\.10[^#]*10\.10\.20\.15[^#]*dport 22' \
  "sudo -n nft list chain inet filter forward"

for _m04_h in gw01 dns01 git01 runner01; do
  check_ssh "$_m04_h : clé ansible-ci autorisée pour admin, restreinte à 10.10.20.15" "$_m04_h" \
    'grep -Eq "^from=\"[^\"]*10\.10\.20\.15[^\"]*\".*ansible-ci" "$HOME/.ssh/authorized_keys"'
done
check_cmd "adm01 : clé ansible-ci autorisée, restreinte à 10.10.20.15" \
  grep -Eq '^from="[^"]*10\.10\.20\.15[^"]*".*ansible-ci' "$HOME/.ssh/authorized_keys"

title "Documentation"
check_cmd "matrice des flux : flux SSH de runner01 vers gw01 et adm01" \
  _m04_doc_contient "$_M04_DOC/matrice-flux.md" 'runner01|10\.10\.20\.15' 'adm01|10\.10\.10\.10' 'gw01|10\.10\.10\.1'
check_cmd "registre des secrets : clé ansible-ci inscrite" \
  _m04_doc_contient "$_M04_DOC/registre-secrets.md" 'ansible-ci'
