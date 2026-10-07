# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($g, $h sont des variables jq)
#
# check-E12.sh — M06-E12 : Inventaire Ansible depuis NetBox
# À lancer depuis adm01. Lecture seule : ansible-inventory sur la copie de travail ~/src/ansible
# (aucun hôte contacté), API NetBox et GitLab en lecture.

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E12 — Inventaire Ansible depuis NetBox"
require_cmd git jq curl

_m06o_inv="$_M06O_ANSIBLE/inventories/lab/netbox.yml"
_m06o_req="$_M06O_ANSIBLE/collections/requirements.yml"
_m06o_env="$_M06O_CFG/netbox-ansible.env"

_m06o_version_figee() {
  grep -A2 -E 'name:[[:space:]]*netbox\.netbox' "$_m06o_req" | grep -Eq 'version:[[:space:]]*["'"'"']?(==)?3\.23\.0["'"'"']?[[:space:]]*(#.*)?$'
}
_m06o_sans_secret() {
  [[ -s "$_m06o_inv" ]] && ! grep -Eq 'nbt_[A-Za-z0-9]+\.|validate_certs:[[:space:]]*(false|no)' "$_m06o_inv"
}
# Jeton de netbox-ansible.env (lu sans exécuter le fichier) en lecture seule ?
_m06o_jeton_lecture() {
  sed -nE 's/^(export[[:space:]]+)?NETBOX_TOKEN="?([^"]*)"?.*/\2/p' "$_m06o_env" | head -n 1 >"$_M06O_TMP/jeton"
  _m06o_jeton_lecture_seule "$_M06O_TMP/jeton"
}
_m06o_ci_compare() { _m06o_contenu_main "$_M06O_PROJET_ANSIBLE" .gitlab-ci.yml | grep -q 'comparer-inventaires'; }

check_cmd "collections/requirements.yml : collection netbox.netbox déclarée" \
  grep -Eq 'name:[[:space:]]*netbox\.netbox' "$_m06o_req"
check_cmd "collections/requirements.yml : version figée 3.23.0 (exacte, pas une plage)" _m06o_version_figee
check_cmd "inventories/lab/netbox.yml publié sur main" \
  _m06o_fichier_main "$_M06O_PROJET_ANSIBLE" inventories/lab/netbox.yml
check_cmd "netbox.yml : plugin netbox.netbox.nb_inventory" \
  grep -Eq '^plugin:[[:space:]]*netbox\.netbox\.nb_inventory[[:space:]]*$' "$_m06o_inv"
check_cmd "netbox.yml : aucun jeton en clair, TLS non désactivé" _m06o_sans_secret
check_cmd "netbox-ansible.env présent, en mode 600" _m06o_mode600 "$_m06o_env"
check_cmd "le jeton de netbox-ansible.env est en lecture seule" _m06o_jeton_lecture
check_output "ansible.cfg : l'inventaire par défaut est netbox.yml" 'netbox\.yml' \
  _m06o_ans ansible-config dump --only-changed

# --- Les deux inventaires décrivent le même socle -------------------------------------------------------
_m06o_nb_inv="$(_m06o_inventaire inventories/lab/netbox.yml)"
_m06o_pve_inv="$(_m06o_inventaire inventories/lab/proxmox.yml)"
check_cmd "l'inventaire NetBox se lit et contient le groupe socle" \
  jq -e '.groupes.socle | length > 0' <<<"$_m06o_nb_inv"
for _m06o_paire in role_routeur:gw01 role_bastion:adm01 role_dns:dns01 role_gitlab:git01 role_runner:runner01; do
  check_cmd "inventaire NetBox : ${_m06o_paire#*:} dans ${_m06o_paire%%:*}" \
    jq -e --arg g "${_m06o_paire%%:*}" --arg h "${_m06o_paire#*:}" '(.groupes[$g] // []) | index($h) != null' <<<"$_m06o_nb_inv"
done
for _m06o_h in gw01 adm01 dns01 git01; do
  check_output "inventaire NetBox : ansible_host de $_m06o_h = ${_M06O_IP[$_m06o_h]}" "^${_M06O_IP[$_m06o_h]}\$" \
    jq -r --arg h "$_m06o_h" '.adresses[$h] // empty' <<<"$_m06o_nb_inv"
done
check_cmd "inventaires NetBox et Proxmox identiques (groupes socle/role_*, adresses)" \
  test -n "$_m06o_nb_inv" -a "$_m06o_nb_inv" == "$_m06o_pve_inv"
check_cmd "outils/comparer-inventaires.sh présent et exécutable" test -x "$_M06O_ANSIBLE/outils/comparer-inventaires.sh"
check_cmd "le pipeline de main appelle la comparaison des inventaires" _m06o_ci_compare
