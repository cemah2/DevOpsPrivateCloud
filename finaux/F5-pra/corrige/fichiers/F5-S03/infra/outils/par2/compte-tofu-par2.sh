#!/usr/bin/env bash
# outils/par2/compte-tofu-par2.sh — compte d'automatisation OpenTofu de PAR2 sur l'API Proxmox VE de
# hp01 (F5-S03). Projet plateforme/infra. À lancer EN ROOT SUR hp01, une fois (idempotent).
#
# Même principe que pve-tofu-compte.sh (M05-E03) : un utilisateur sans mot de passe, un rôle à
# privilèges minimaux, un jeton à séparation de privilèges, des ACL limitées à ce qu'OpenTofu crée :
#   /pool/par2                          les VMs du site (création, configuration, alimentation)
#   /storage/par2-vms                   disques et lecteurs cloud-init
#   /sdn/zones/localnetwork/vmbr2       droit d'utiliser le pont vmbr2 (SDN.Use, PVE 8 et suivants)
#   /vms/<VMID du template>             clonage de l'image dorée (lecture et clone)
# Le jeton n'a AUCUN droit sur / ni sur la configuration de l'hôte, ni sur PBS (autre service).
#
# Usage : compte-tofu-par2.sh <VMID-DU-TEMPLATE>   → affiche le secret du jeton UNE fois (à mettre
#         dans Ansible Vault « critique » : vault_pve_par2_jeton, puis ~/.config/workbook/pve-par2.env).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur hp01" >&2; exit 2; }
tpl="${1:?usage : $0 <VMID-DU-TEMPLATE>}"
user=wb-tofu@pve
jeton=par2
role=WBTofuPar2

privs=(
  VM.Allocate VM.Clone VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network
  VM.Config.Cloudinit VM.Config.Options VM.Config.HWType VM.Config.CDROM VM.PowerMgmt VM.GuestAgent.Audit
  Datastore.AllocateSpace Datastore.Audit Pool.Audit SDN.Use Sys.Audit
)

if pveum role list --output-format json | jq -e --arg r "$role" 'any(.[]; .roleid == $r)' >/dev/null; then
  pveum role modify "$role" --privs "${privs[*]}"
else
  pveum role add "$role" --privs "${privs[*]}"
fi
pveum user list --output-format json | jq -e --arg u "$user" 'any(.[]; .userid == $u)' >/dev/null \
  || pveum user add "$user" --comment "OpenTofu de PAR2 (plateforme/infra envs/par2) — F5-S03"

for chemin in /pool/par2 /storage/par2-vms /sdn/zones/localnetwork/vmbr2 "/vms/$tpl"; do
  pveum acl modify "$chemin" --tokens "$user!$jeton" --roles "$role"
  pveum acl modify "$chemin" --users "$user" --roles "$role"
done

if pveum user token list "$user" --output-format json | jq -e --arg t "$jeton" 'any(.[]; .tokenid == $t)' >/dev/null; then
  echo "jeton $user!$jeton déjà présent (secret non réaffiché) ; rotation : pveum user token remove puis relance"
else
  pveum user token add "$user" "$jeton" --privsep 1 --comment "OpenTofu envs/par2" --output-format json \
    | jq -r '"PROXMOX_VE_API_TOKEN=\(.["full-tokenid"])=\(.value)"'
  echo "⚠️ secret affiché une seule fois : range-le dans Ansible Vault « critique » (vault_pve_par2_jeton)."
fi
pveum user token permissions "$user" "$jeton" --path /pool/par2
