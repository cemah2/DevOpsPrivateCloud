#!/usr/bin/env bash
# configurer-env.sh — enchaîner OpenTofu (création) et Ansible (configuration) (M05-E23).
#
# Usage, après un « tofu apply » réussi dans envs/<ENV> :
#   outils/configurer-env.sh lab-m05 [--check]
#
# 1. lit dans l'état la liste des hôtes (sortie hotes_ansible), sans rien modifier ;
# 2. vérifie que l'inventaire dynamique d'Ansible les voit (étiquettes posées par OpenTofu) ;
# 3. lance playbooks/<ENV>.yml limité à ces hôtes, depuis plateforme/ansible.
# Aucun « provisioner » dans le code OpenTofu : les deux outils restent indépendants, chacun
# rejouable seul, chacun avec son propre journal.
set -euo pipefail

env="${1:?usage : $0 ENV [--check]   (ex. lab-m05)}"
shift
infra="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
ansible="${ANSIBLE_PROJET:-${WB_SRC:-$HOME/src}/ansible}"
playbook="playbooks/env-${env#lab-}.yml"   # lab-m05 -> playbooks/env-m05.yml

command -v jq >/dev/null || { echo "jq introuvable" >&2; exit 2; }
[[ -f "$ansible/$playbook" ]] || { echo "Playbook absent : $ansible/$playbook" >&2; exit 2; }

set -a
# shellcheck source=/dev/null
. "$HOME/.config/workbook/pve-tofu.env"
# shellcheck source=/dev/null
. "$HOME/.config/workbook/s3-tofu.env"
set +a

hotes="$(cd "$infra/envs/$env" && tofu output -json hotes_ansible | jq -r 'join(",")')"
[[ -n "$hotes" ]] || { echo "Aucun hôte dans la sortie hotes_ansible de $env." >&2; exit 1; }
echo "Hôtes de $env : $hotes"

cd "$ansible"
set -a
# shellcheck source=/dev/null
. "$HOME/.config/workbook/pve-ansible.env"
set +a
vus="$(uv run ansible-inventory --list 2>/dev/null | jq -r '._meta.hostvars | keys[]')"
manquants=()
for h in ${hotes//,/ }; do
  grep -qx "$h" <<<"$vus" || manquants+=("$h")
done
if ((${#manquants[@]})); then
  echo "Absents de l'inventaire Ansible : ${manquants[*]} (étiquettes ? filtre de proxmox.yml ?)" >&2
  exit 1
fi

uv run ansible-playbook "$playbook" --limit "$hotes" "$@"
