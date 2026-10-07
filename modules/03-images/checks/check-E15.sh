# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E15.sh — M03-E15 « Pipeline de construction d'images »
# runner01 sait construire (Packer, plugin, flux), le pipeline est décrit sur main, planifié,
# sérialisé, ses secrets sont protégés, et il a déjà publié une image testée.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E15 — Pipeline de construction d'images"
require_cmd jq ssh curl
_m03_charger

title "runner01 : outils et flux"
check_ssh_output "runner01 : Packer 1.16 installé" runner01 '^Packer v1\.16\.' "packer version"
check_ssh_output "runner01 : plugin proxmox installé pour gitlab-runner" runner01 'github\.com/hashicorp/proxmox' \
  "sudo -n -u gitlab-runner -H packer plugins installed"
check_ssh "runner01 → pve01 : API (TCP 8006) joignable" runner01 \
  'ip=$(getent ahostsv4 pve01.par1.medisphere.internal | awk "NR==1{print \$1}"); [ -n "$ip" ] && timeout 5 bash -c "exec 3<>/dev/tcp/$ip/8006"'
check_ssh "runner01 : le certificat de l'API de pve01 est approuvé par le magasin système (TLS vérifié)" runner01 \
  'ip=$(getent ahostsv4 pve01.par1.medisphere.internal | awk "NR==1{print \$1}"); curl -s -o /dev/null --max-time 5 "https://$ip:8006/api2/json/version"'
check_ssh_output "pve01 : IPSet automation du pare-feu contient runner01" "$WB_PVE_HOST" '10\.10\.20\.15' \
  "pvesh get /cluster/firewall/ipset/automation --output-format json"
check_ssh_output "gw01 : règle vsandbox → runner01 TCP 8100-8199 (serveur HTTP de Packer)" gw01 \
  '10\.10\.20\.15.*8100-8199|8100-8199.*10\.10\.20\.15' "sudo -n nft list chain inet filter forward"
check_ssh_output "gw01 : règle runner01 → vsandbox TCP 22 (communicateur SSH)" gw01 \
  '10\.10\.20\.15.*(dport 22|dport \{[^}]*22)' "sudo -n nft list chain inet filter forward"

title "Projet plateforme/images"
check_cmd "projet plateforme/images présent" _m03_api_ok "$_M03_PROJET" '.archived == false'
check_cmd ".gitlab-ci.yml sur main : un seul build à la fois (resource_group)" \
  _m03_fichier_main_contient .gitlab-ci.yml 'resource_group:'
check_cmd ".gitlab-ci.yml sur main : jobs selon la source (planifié, MR)" \
  _m03_fichier_main_contient .gitlab-ci.yml 'CI_PIPELINE_SOURCE.*schedule'
check_cmd ".gitlab-ci.yml sur main : l'image est testée avant publication" \
  _m03_fichier_main_contient .gitlab-ci.yml 'tester-image\.sh'
check_cmd "pipeline planifié actif sur main" _m03_api_ok "$_M03_PROJET/pipeline_schedules" \
  'any(.[]; .active and (.ref == "main" or .ref == "refs/heads/main"))'
check_cmd "secret PKR_VAR_proxmox_token : variable protégée et masquée" \
  _m03_api_ok "$_M03_PROJET/variables/PKR_VAR_proxmox_token" '.protected and (.masked or (.masked_and_hidden // false))'
check_cmd "aucun secret Proxmox dans les fichiers du dépôt (vars/)" \
  bash -c '! grep -REqi "token[^=]*= *\"[0-9a-f]{8}-[0-9a-f]{4}-" "$1/vars" "$1/.gitlab-ci.yml" 2>/dev/null' _ "$_M03_SRC"

# Un pipeline réussi de main dont un job de l'étape publish a réussi.
_m03_e15_publie() {
  local ids pid
  ids="$(gitlab_api "$_M03_PROJET/pipelines?ref=main&status=success&per_page=20" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    gitlab_api "$_M03_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -e 'any(.[]; .stage == "publish" and .status == "success")' >/dev/null && return 0
  done
  return 1
}
check_cmd "un pipeline de main a construit, testé et publié une image (étape publish réussie)" _m03_e15_publie
_m03_a_current() { [[ -n "$(_m03_current "$1")" ]]; }
check_cmd "une seule image dorée Debian « current »" _m03_a_current debian13

title "Documentation"
check_cmd "matrice des flux : flux de construction (8100-8199, 8006, runner01)" \
  _m03_doc_contient "$_M03_DOC/matrice-flux.md" '8100-8199' '8006' 'runner01|10\.10\.20\.15'
check_cmd "registre des secrets : jeton wb-packer inscrit" \
  _m03_doc_contient "$_M03_DOC/registre-secrets.md" 'wb-packer'
