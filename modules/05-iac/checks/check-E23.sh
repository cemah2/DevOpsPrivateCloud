# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E23.sh — M05-E23 : De OpenTofu à Ansible, inventaire et configuration après création
# Lecture seule : inventaire dynamique (ansible-inventory), sorties de l'état (tofu output),
# intérieur de la VM 2054 par l'agent QEMU (commandes de lecture), code des deux projets.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E23 — De OpenTofu à Ansible : inventaire et configuration après création"
require_cmd jq tofu uv

check_cmd "infra : aucun provisioner dans le code (ni local-exec, ni remote-exec)" \
  bash -c '! grep -rEqs --include="*.tf" "provisioner[[:space:]]+\"" "$1/socle" "$1/envs"' _ "$_m05o_infra"
_m05o_hotes() { _m05o_tofu "$_m05o_lab" output -json hotes_ansible | jq -r '.[]'; }
check_output "lab-m05 : sortie hotes_ansible (noms des VMs pour Ansible)" '^m05-jetable$' _m05o_hotes
check_cmd "infra : outils/configurer-env.sh exécutable" test -x "$_m05o_infra/outils/configurer-env.sh"

_m05o_inv="$(_m05o_ansible ansible-inventory --list 2>/dev/null || true)"
check_cmd "inventaire dynamique : groupe env_m05 avec m05-jetable" \
  bash -c 'jq -e ".env_m05.hosts // [] | index(\"m05-jetable\") != null" <<<"$1" >/dev/null' _ "$_m05o_inv"
check_output "inventaire dynamique : adresse de m05-jetable lue par l'agent (10.10.99.x)" '^10\.10\.99\.[0-9]+$' \
  jq -r '._meta.hostvars["m05-jetable"].ansible_host // empty' <<<"$_m05o_inv"
check_cmd "inventaire dynamique : le socle est toujours complet (six hôtes dans socle)" \
  bash -c '[ "$(jq -r ".socle.hosts // [] | length" <<<"$1")" = 6 ]' _ "$_m05o_inv"
check_cmd "inventaire dynamique : aucune VM d'environnement dans le groupe socle" \
  bash -c '! jq -r ".socle.hosts // [] | .[]" <<<"$1" | grep -q "^m05-"' _ "$_m05o_inv"
check_cmd "ansible : VMs d'environnement en accept-new dans un known_hosts dédié (jamais StrictHostKeyChecking=no)" \
  bash -c 'g="$1/inventories/lab/group_vars/env_m05"; grep -rqs "StrictHostKeyChecking=accept-new" "$g" && ! grep -rqis "StrictHostKeyChecking=no" "$1/inventories" "$1/ansible.cfg"' _ "$_m05o_ansible"

# --- La VM a bien été configurée par le rôle base (lu par l'agent QEMU) ------------------------------
check_output "m05-jetable : fuseau Europe/Paris (rôle base)" '^Europe/Paris' \
  _m05o_invite 2054 timedatectl show --property=Timezone --value
check_output "m05-jetable : chrony interroge la passerelle du VLAN 99" '10\.10\.99\.1' \
  _m05o_invite 2054 chronyc -n sources
check_output "m05-jetable : journal persistant (rôle base)" 'Storage=persistent' \
  _m05o_invite 2054 systemd-analyze cat-config systemd/journald.conf
