#!/usr/bin/env bash
# capi/pve-compte-capi.sh — compte, rôles, jeton et ACL de Cluster API (CAPMOX) sur Proxmox VE 9
# (M18-E08, PLAT-1908). À lancer en root sur pve01, APRÈS l'avoir relu. Rejouable : ce qui existe
# n'est pas recréé (les rôles sont remis à la liste ci-dessous). Le secret du jeton n'est affiché
# qu'à sa création.
#
# Modèle : section « Proxmox RBAC with least privileges » de la documentation de CAPMOX v0.9.1
# (rôles intégrés sur des pools et un stockage dédiés), adaptée au lab :
#   - un seul pool « lab » (PLAN.md §4.3 bis) : les VMs clonées ET le template y sont ;
#   - un rôle personnalisé WBCapi plutôt que PVEVMAdmin (liste écrite, relue, et validée par
#     Proxmox VE 9 lui-même : « pveum role add » refuse un privilège inconnu, comme VM.Monitor,
#     supprimé en PVE 9) ;
#   - un stockage DÉDIÉ « capi-iso » pour les ISO cloud-init que CAPMOX téléverse (une par VM).
#
# Variables facultatives : STOCKAGE_VM (local-nvme), POOL (lab), ZONE_SDN (lab), VNET (vk8s),
#   STOCKAGE_ISO_CAPI (capi-iso), CHEMIN_ISO_CAPI (/mnt/hdd-bulk/capi-iso).
set -euo pipefail

STOCKAGE_VM="${STOCKAGE_VM:-local-nvme}"
POOL="${POOL:-lab}"
ZONE_SDN="${ZONE_SDN:-lab}"
VNET="${VNET:-vk8s}"
STOCKAGE_ISO_CAPI="${STOCKAGE_ISO_CAPI:-capi-iso}"
CHEMIN_ISO_CAPI="${CHEMIN_ISO_CAPI:-/mnt/hdd-bulk/capi-iso}"
UTILISATEUR="wb-capi@pve"
JETON="capi"

# Privilèges sur le pool : chacun correspond à un appel de CAPMOX v0.9.1 (lecture du code :
# internal/service/vmservice, pkg/proxmox/goproxmox).
PRIVS_VM=(
  VM.Allocate                 # créer (clone) et supprimer les VMs ; ajouter la VM au pool
  VM.Clone                    # cloner le template 9060
  VM.Audit                    # lire configuration et état, chercher le template (tags)
  VM.Config.CDROM             # monter puis démonter l'ISO cloud-init (ide0)
  VM.Config.CPU               # numSockets, numCores
  VM.Config.Memory            # memoryMiB
  VM.Config.Disk              # agrandir le disque de démarrage (bootVolume)
  VM.Config.Network           # carte réseau sur le VNet vk8s
  VM.Config.Options           # description, étiquettes (tags)
  VM.Config.Cloudinit         # paramètres cloud-init de la VM
  VM.Config.HWType            # type de matériel hérité du template
  VM.PowerMgmt                # démarrer, arrêter
  VM.GuestAgent.Audit         # attendre l'agent QEMU, lire les adresses (PVE 8 : VM.Monitor)
  VM.GuestAgent.Unrestricted  # « cloud-init status » exécuté par l'agent (exec) ; à retirer si
                              # les ProxmoxMachines portent checks.skipCloudInitStatus: true
)

existe() { pvesh get "$1" >/dev/null 2>&1; }

# --- Stockage dédié aux ISO cloud-init (répertoire sur hdd-bulk, contenu « iso » seulement) -------
# ⚠️ Modifie la configuration de stockage de pve01 (/etc/pve/storage.cfg). Retour arrière :
#    pvesm remove capi-iso ; rmdir CHEMIN_ISO_CAPI (vide).
if ! pvesm status --storage "$STOCKAGE_ISO_CAPI" >/dev/null 2>&1; then
  install -d -m 0755 "$CHEMIN_ISO_CAPI"
  pvesm add dir "$STOCKAGE_ISO_CAPI" --path "$CHEMIN_ISO_CAPI" --content iso
fi

# --- Rôles ----------------------------------------------------------------------------------
if existe "/access/roles/WBCapi"; then
  pveum role modify WBCapi --privs "${PRIVS_VM[*]}"
else
  pveum role add WBCapi --privs "${PRIVS_VM[*]}"
fi
# Lecture de l'état des nœuds (mémoire disponible : ordonnanceur de CAPMOX, schedulerHints).
if existe "/access/roles/WBCapiAudit"; then
  pveum role modify WBCapiAudit --privs "Sys.Audit"
else
  pveum role add WBCapiAudit --privs "Sys.Audit"
fi

# --- Utilisateur et jeton (séparation des privilèges : ACL sur l'utilisateur ET le jeton) ------
existe "/access/users/$UTILISATEUR" \
  || pveum user add "$UTILISATEUR" --comment "Compte technique Cluster API / CAPMOX (PLAT-1908, M18)"
if existe "/access/users/$UTILISATEUR/token/$JETON"; then
  echo "jeton $UTILISATEUR!$JETON déjà présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans ~/.config/workbook/pve-capi.env sur adm01."
  pveum user token add "$UTILISATEUR" "$JETON" --privsep 1 \
    --expire "$(date -d '+90 days' +%s)" --comment "CAPMOX, cluster capi-essai (M18)"
fi

acl() { # acl CHEMIN RÔLE [--propagate 0|1]
  local chemin="$1" role="$2"; shift 2
  pveum acl modify "$chemin" --users "$UTILISATEUR" --roles "$role" "$@"
  pveum acl modify "$chemin" --tokens "$UTILISATEUR!$JETON" --roles "$role" "$@"
}
acl "/pool/$POOL" WBCapi
acl "/" WBCapiAudit --propagate 0
acl "/nodes" WBCapiAudit
acl "/storage/$STOCKAGE_VM" PVEDatastoreUser          # AllocateSpace + Audit : disques des clones
acl "/storage/$STOCKAGE_ISO_CAPI" PVEDatastoreAdmin   # téléverser et supprimer les ISO cloud-init
acl "/sdn/zones/$ZONE_SDN/$VNET" PVESDNUser           # brancher les VMs sur vk8s (VLAN 40) seulement

# --- Contrôle ---------------------------------------------------------------------------------
for chemin in "/pool/$POOL" "/nodes" "/storage/$STOCKAGE_VM" "/storage/$STOCKAGE_ISO_CAPI" "/sdn/zones/$ZONE_SDN/$VNET"; do
  echo "== droits effectifs du jeton sur $chemin"
  pveum user token permissions "$UTILISATEUR" "$JETON" --path "$chemin"
done
