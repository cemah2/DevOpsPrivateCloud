#!/usr/bin/env bash
# pve-ansible-compte.sh — compte, rôles, jeton et ACL d'Ansible sur Proxmox VE 9 (M04-E13).
# À lancer en root sur pve01. Rejouable : ce qui existe n'est pas recréé (les rôles sont
# remis à la liste ci-dessous). Le secret du jeton n'est affiché qu'à sa création.
#
# Périmètre M04-E13 : LECTURE de l'inventaire. Les droits de clonage et de destruction des
# instances Molecule sont ajoutés au rôle WBAnsible en M04-E24, pas avant.
#
# Variable facultative : POOL (lab).
set -euo pipefail

POOL="${POOL:-lab}"
UTILISATEUR="wb-ansible@pve"
JETON="ansible"

# Privilèges : chacun correspond à un appel de l'API fait par le plugin d'inventaire
# community.proxmox.proxmox 2.x (contrôles relevés dans l'API viewer de Proxmox VE 9).
PRIVS_POOL=(
  VM.Audit             # /cluster/resources (filtré), /nodes/…/qemu/{vmid}/config, status/current, snapshot
  VM.GuestAgent.Audit  # /nodes/…/qemu/{vmid}/agent/network-get-interfaces (PVE 8 : VM.Monitor)
  Pool.Audit           # /pools et /pools?poolid=lab : groupe proxmox_pool_lab
)
# /cluster/status exige Sys.Audit sur « / » : rôle séparé, posé SANS propagation, pour ne
# rien ouvrir d'autre que ce chemin (en particulier aucune VM hors du pool lab).
PRIVS_CLUSTER=(
  Sys.Audit
)

existe() { pvesh get "$1" >/dev/null 2>&1; }

role() { # role NOM PRIVILÈGES
  if existe "/access/roles/$1"; then
    pveum role modify "$1" --privs "$2"
  else
    pveum role add "$1" --privs "$2"
  fi
}
role WBAnsible "${PRIVS_POOL[*]}"
role WBAnsibleCluster "${PRIVS_CLUSTER[*]}"

existe "/access/users/$UTILISATEUR" \
  || pveum user add "$UTILISATEUR" --comment "Compte technique Ansible, plateforme/ansible (PLAT-523)"
if existe "/access/users/$UTILISATEUR/token/$JETON"; then
  echo "jeton $UTILISATEUR!$JETON déjà présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-ansible.env sur adm01."
  pveum user token add "$UTILISATEUR" "$JETON" --privsep 1 \
    --expire "$(date -d '+1 year' +%s)" --comment "Inventaire dynamique Ansible (PLAT-523)"
fi

# ACL sur l'utilisateur ET sur le jeton : un jeton privsep n'a que l'intersection des deux.
acl() { # acl CHEMIN RÔLE PROPAGATION
  pveum acl modify "$1" --users "$UTILISATEUR" --roles "$2" --propagate "$3"
  pveum acl modify "$1" --tokens "$UTILISATEUR!$JETON" --roles "$2" --propagate "$3"
}
acl "/pool/$POOL" WBAnsible 1
acl "/" WBAnsibleCluster 0

for chemin in / "/pool/$POOL" /vms; do
  echo "== droits effectifs du jeton sur $chemin"
  pveum user token permissions "$UTILISATEUR" "$JETON" --path "$chemin"
done
