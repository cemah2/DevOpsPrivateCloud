#!/usr/bin/env bash
# pve-packer-compte.sh — compte, rôles, jeton et ACL de Packer sur Proxmox VE 9 (M03-E02).
# À lancer en root sur pve01. Rejouable : ce qui existe déjà n'est pas recréé
# (le rôle est remis à la liste ci-dessous). Le secret du jeton n'est affiché qu'à sa création.
#
# Variables facultatives : STOCKAGE_VM (local-nvme), STOCKAGE_ISO (hdd-bulk),
#                          ZONE_SDN (lab), VNET_BUILD (vsandbox), POOL (lab).
set -euo pipefail

STOCKAGE_VM="${STOCKAGE_VM:-local-nvme}"
STOCKAGE_ISO="${STOCKAGE_ISO:-hdd-bulk}"
ZONE_SDN="${ZONE_SDN:-lab}"
VNET_BUILD="${VNET_BUILD:-vsandbox}"
POOL="${POOL:-lab}"
UTILISATEUR="wb-packer@pve"
JETON="packer"

# Privilèges : chacun est exigé par un appel de l'API que fait le plugin proxmox
# (contrôles relevés dans l'API viewer de Proxmox VE 9, voir le corrigé de M03-E02).
PRIVS_VM=(
  VM.Allocate          # créer la VM de build, la supprimer (-force), la convertir en template
  VM.Clone             # proxmox-clone : cloner le template source
  VM.Audit             # lire configuration et état (suivi du build)
  VM.Config.CDROM      # ISO d'installation, lecteur cloud-init
  VM.Config.CPU        # cores, type de CPU
  VM.Config.Cloudinit  # ciuser/sshkeys/ipconfig des builds par clonage, réglages du template
  VM.Config.Disk       # disque système
  VM.Config.HWType     # contrôleur SCSI, affichage, port série
  VM.Config.Memory     # mémoire
  VM.Config.Network    # carte réseau sur le VNet de build
  VM.Config.Options    # nom, description (manifeste), étiquettes, agent, ordre de démarrage
  VM.Console           # boot_command : frappes envoyées par l'API « sendkey »
  VM.PowerMgmt         # démarrer, arrêter
  VM.GuestAgent.Audit  # lire l'adresse IP de la VM par l'agent QEMU (PVE 8 : VM.Monitor)
)

existe() { pvesh get "$1" >/dev/null 2>&1; }

# --- Rôles --------------------------------------------------------------------------
if existe "/access/roles/WBPacker"; then
  pveum role modify WBPacker --privs "${PRIVS_VM[*]}"
else
  pveum role add WBPacker --privs "${PRIVS_VM[*]}"
fi
# Lecture seule du stockage des ISO : suffit pour monter une ISO déjà déposée.
if existe "/access/roles/WBLectureISO"; then
  pveum role modify WBLectureISO --privs "Datastore.Audit"
else
  pveum role add WBLectureISO --privs "Datastore.Audit"
fi

# --- Utilisateur et jeton -------------------------------------------------------------
existe "/access/users/$UTILISATEUR" \
  || pveum user add "$UTILISATEUR" --comment "Compte technique Packer, plateforme/images (SEC-402)"
if existe "/access/users/$UTILISATEUR/token/$JETON"; then
  echo "jeton $UTILISATEUR!$JETON déjà présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-packer.env sur adm01."
  pveum user token add "$UTILISATEUR" "$JETON" --privsep 1 \
    --expire "$(date -d '+1 year' +%s)" --comment "Builds Packer (SEC-402)"
fi

# --- ACL : sur l'utilisateur ET sur le jeton (privsep = intersection des deux) ------------
acl() { # acl CHEMIN RÔLE
  pveum acl modify "$1" --users "$UTILISATEUR" --roles "$2"
  pveum acl modify "$1" --tokens "$UTILISATEUR!$JETON" --roles "$2"
}
acl "/pool/$POOL" WBPacker
acl "/storage/$STOCKAGE_VM" PVEDatastoreUser
acl "/storage/$STOCKAGE_ISO" WBLectureISO
acl "/sdn/zones/$ZONE_SDN/$VNET_BUILD" PVESDNUser

# --- Contrôle -------------------------------------------------------------------------
for chemin in "/pool/$POOL" "/storage/$STOCKAGE_VM" "/storage/$STOCKAGE_ISO" "/sdn/zones/$ZONE_SDN/$VNET_BUILD"; do
  echo "== droits effectifs du jeton sur $chemin"
  pveum user token permissions "$UTILISATEUR" "$JETON" --path "$chemin"
done
