#!/usr/bin/env bash
# pve-tofu-compte.sh — compte, rôle, jeton et ACL d'OpenTofu sur Proxmox VE 9 (M05-E03).
# À lancer en root sur pve01. Rejouable : ce qui existe n'est pas recréé (le rôle est remis
# à la liste ci-dessous, les ACL sont reposées). Le secret du jeton n'est affiché qu'à sa
# création : copie-le aussitôt dans ~/.config/workbook/pve-tofu.env sur adm01.
#
# Périmètre de M05-E03 : les VMs d'environnement (pool lab, disques sur local-nvme, VNet
# vsandbox). M05-E10 (s3-01 : VNet vinfra, disque de données sur hdd-bulk) relance ce script
# en élargissant les deux listes, sans rien changer d'autre :
#   VNETS="vsandbox vinfra" STOCKAGES="local-nvme hdd-bulk" ./pve-tofu-compte.sh
#
# Variables facultatives : POOL (lab), ZONE_SDN (lab), VNETS (vsandbox),
#                          STOCKAGES (local-nvme), EXPIRATION_JOURS (365), JETON (tofu).
set -euo pipefail

POOL="${POOL:-lab}"
ZONE_SDN="${ZONE_SDN:-lab}"
VNETS="${VNETS:-vsandbox}"
STOCKAGES="${STOCKAGES:-local-nvme}"
EXPIRATION_JOURS="${EXPIRATION_JOURS:-365}"
UTILISATEUR="wb-tofu@pve"
JETON="${JETON:-tofu}" # rotation : JETON=tofu2 ./pve-tofu-compte.sh

# Privilèges sur /pool/lab. Chacun correspond à un appel de l'API que fait la ressource
# proxmox_virtual_environment_vm du provider bpg/proxmox 0.115 (contrôles relevés dans
# l'API viewer de Proxmox VE 9).
PRIVS_POOL=(
  VM.Audit            # lire config et état (refresh), lister les VMs (source de données vms)
  VM.Clone            # POST …/qemu/{template}/clone : le template est dans le pool
  VM.Allocate         # clone avec « pool=lab » (contrôle sur /pool/lab), DELETE …/qemu/{vmid}
  VM.Config.CPU       # cores, type de CPU
  VM.Config.Memory    # mémoire
  VM.Config.Disk      # agrandir le disque cloné, disques de données, lecteur cloud-init
  VM.Config.CDROM     # le lecteur cloud-init est un média « cdrom »
  VM.Config.Network   # carte réseau sur le VNet
  VM.Config.HWType    # contrôleur SCSI, port série, affichage
  VM.Config.Options   # nom, description, étiquettes, on_boot, ordre de démarrage, agent, type d'OS
  VM.Config.Cloudinit # utilisateur, clés, adresse, résolveur
  VM.PowerMgmt        # démarrer, arrêter, éteindre avant destruction
  VM.GuestAgent.Audit # lire les adresses IP par l'agent QEMU (PVE 8 : VM.Monitor)
  Pool.Audit          # lire l'appartenance au pool (détection de dérive du provider)
)
# Écartés volontairement : VM.Console (le provider ne tape rien au clavier), VM.Migrate (un
# seul nœud), VM.Snapshot*, VM.Backup (PBS s'en charge), VM.GuestAgent.Unrestricted et
# VM.GuestAgent.File* (exécuter ou lire dans l'invité), Pool.Allocate, Sys.*, Permissions.*,
# Datastore.Allocate (supprimer n'importe quel volume du stockage).

existe() { pvesh get "$1" >/dev/null 2>&1; }

# --- Rôle -------------------------------------------------------------------------------
if existe "/access/roles/WBTofu"; then
  pveum role modify WBTofu --privs "${PRIVS_POOL[*]}"
else
  pveum role add WBTofu --privs "${PRIVS_POOL[*]}"
fi

# --- Utilisateur et jeton -----------------------------------------------------------------
existe "/access/users/$UTILISATEUR" \
  || pveum user add "$UTILISATEUR" --comment "Compte technique OpenTofu, plateforme/infra (SEC-603)"
if existe "/access/users/$UTILISATEUR/token/$JETON"; then
  echo "jeton $UTILISATEUR!$JETON déjà présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-tofu.env sur adm01."
  pveum user token add "$UTILISATEUR" "$JETON" --privsep 1 \
    --expire "$(date -d "+${EXPIRATION_JOURS} days" +%s)" --comment "OpenTofu, plateforme/infra (SEC-603)"
fi

# --- ACL : sur l'utilisateur ET sur le jeton (privsep : le jeton n'a que l'intersection) ---
acl() { # acl CHEMIN RÔLE
  pveum acl modify "$1" --users "$UTILISATEUR" --roles "$2"
  pveum acl modify "$1" --tokens "$UTILISATEUR!$JETON" --roles "$2"
}
read -ra liste_stockages <<<"$STOCKAGES"
read -ra liste_vnets <<<"$VNETS"
chemins=("/" "/pool/$POOL")

acl "/pool/$POOL" WBTofu
for s in "${liste_stockages[@]}"; do
  existe "/storage/$s" || { echo "stockage inconnu : $s" >&2; exit 1; }
  acl "/storage/$s" PVEDatastoreUser # Datastore.AllocateSpace + Datastore.Audit
  chemins+=("/storage/$s")
done
for v in "${liste_vnets[@]}"; do
  existe "/cluster/sdn/vnets/$v" || { echo "VNet inconnu : $v" >&2; exit 1; }
  acl "/sdn/zones/$ZONE_SDN/$v" PVESDNUser # SDN.Use (+ SDN.Audit)
  chemins+=("/sdn/zones/$ZONE_SDN/$v")
done

# --- Contrôle des droits effectifs du JETON -------------------------------------------
# « / » doit être vide : rien hors des chemins ci-dessus.
for chemin in "${chemins[@]}"; do
  echo "== droits effectifs du jeton sur $chemin"
  pveum user token permissions "$UTILISATEUR" "$JETON" --path "$chemin"
done
