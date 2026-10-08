#!/usr/bin/env bash
# hv-droits.sh — pools, groupes, comptes nominatifs, rôle et jeton d'OpenTofu du cluster hv-par1
# (M09-E17, SEC-1027). À lancer en root sur un nœud. Rejouable : ce qui existe n'est pas recréé, le
# rôle WBTofuHV est remis à la liste ci-dessous, les ACL sont reposées.
#
#   MOI=<ton-compte> ./hv-droits.sh
# Les mots de passe des comptes nominatifs sont saisis SANS ÉCHO (pveum passwd), jamais en argument.
# Le secret du jeton n'est affiché qu'à sa création : copie-le aussitôt dans
# ~/.config/workbook/pve-tofu-hv.env (600) sur adm01.
set -euo pipefail

MOI="${MOI:?indique ton compte : MOI=<compte> $0}"
TOFU="wb-tofu-hv@pve"
JETON=tofu
EXPIRATION_JOURS=365

existe() { pvesh get "$1" >/dev/null 2>&1; }

# --- Pools ------------------------------------------------------------------------------------------
# (GET /pools/{poolid} est déprécié en PVE 9 : on lit /pools?poolid=…)
membre() { pvesh get /pools --poolid "$1" --output-format json | grep -q "\"vmid\":$2[,}]"; }
pool_existe() { pvesh get /pools --output-format json | grep -q "\"poolid\":\"$1\""; }
pool_existe prod    || pveum pool add prod    --comment "Production (SEC-1027)"
pool_existe recette || pveum pool add recette --comment "Recette : VMs créées par OpenTofu (SEC-1027)"
for id in 101 102 103 110; do
  membre prod "$id" || pveum pool modify prod --vms "$id" --allow-move 1
done
# Le stockage partagé dans les pools : les membres voient ce qu'ils peuvent utiliser.
pveum pool modify prod --storage ceph-vm
pveum pool modify recette --storage ceph-vm

# --- Groupes et ACL de groupes ----------------------------------------------------------------------
existe /access/groups/hv-admins || pveum group add hv-admins --comment "Administration du cluster hv-par1"
existe /access/groups/hv-ops    || pveum group add hv-ops    --comment "Astreinte : exploitation des VMs"
pveum acl modify / --groups hv-admins --roles Administrator
# Astreinte : TOUT voir (diagnostic), mais n'AGIR que sur les VMs des pools.
pveum acl modify / --groups hv-ops --roles PVEAuditor
pveum acl modify /pool/prod    --groups hv-ops --roles PVEVMUser
pveum acl modify /pool/recette --groups hv-ops --roles PVEVMUser

# --- Comptes nominatifs ------------------------------------------------------------------------------
creer_compte() { # creer_compte UTILISATEUR GROUPE COMMENTAIRE
  if existe "/access/users/$1"; then
    pveum user modify "$1" --groups "$2"
  else
    pveum user add "$1" --groups "$2" --comment "$3"
    echo ">>> Mot de passe de $1 (saisi sans écho) :"
    pveum passwd "$1"
  fi
}
creer_compte "$MOI@pve" hv-admins "Compte nominatif (équipe Plateforme)"
creer_compte "nadia.roussel@pve" hv-ops "Nadia Roussel — astreinte"

# --- Rôle d'OpenTofu ---------------------------------------------------------------------------------
# Base : WBTofu (M05-E03). Le provider bpg/proxmox clone le template 199, configure, démarre, lit les
# adresses par l'agent et détruit. Différences avec pve01 : aucune (pas de migration par OpenTofu).
PRIVS=(
  VM.Audit VM.Clone VM.Allocate
  VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.CDROM VM.Config.Network
  VM.Config.HWType VM.Config.Options VM.Config.Cloudinit
  VM.PowerMgmt        # PVE 9.2 : requis pour DÉMARRER une VM après sa création (start = true)
  VM.GuestAgent.Audit # adresses IP par l'agent
  Pool.Audit
)
# Écartés : VM.Migrate (le placement est l'affaire de la HA et du CRS), VM.Snapshot*, VM.Backup,
# VM.Console, VM.GuestAgent.Unrestricted/File*, Pool.Allocate, Datastore.Allocate, Sys.*, Permissions.*.
if existe /access/roles/WBTofuHV; then
  pveum role modify WBTofuHV --privs "${PRIVS[*]}"
else
  pveum role add WBTofuHV --privs "${PRIVS[*]}"
fi

existe "/access/users/$TOFU" || pveum user add "$TOFU" --comment "Compte technique OpenTofu, envs/hv-invites (SEC-1027)"
if existe "/access/users/$TOFU/token/$JETON"; then
  echo "== jeton $TOFU!$JETON présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-tofu-hv.env sur adm01."
  pveum user token add "$TOFU" "$JETON" --privsep 1 \
    --expire "$(date -d "+${EXPIRATION_JOURS} days" +%s)" --comment "OpenTofu, plateforme/infra envs/hv-invites"
fi

acl() { # acl CHEMIN RÔLE — sur l'utilisateur ET le jeton (privsep : le jeton n'a que l'intersection)
  pveum acl modify "$1" --users "$TOFU" --roles "$2"
  pveum acl modify "$1" --tokens "$TOFU!$JETON" --roles "$2"
}
acl /pool/recette WBTofuHV
acl /vms/199 PVETemplateUser            # cloner le template (VM.Clone + VM.Audit), hors du pool
acl /storage/ceph-vm PVEDatastoreUser   # Datastore.AllocateSpace + Datastore.Audit
acl /sdn/zones/invites/vinv99 PVESDNUser

# --- Contrôles des droits effectifs ---------------------------------------------------------------
echo "== jeton sur / (doit être vide)";            pveum user token permissions "$TOFU" "$JETON" --path /
echo "== jeton sur /pool/prod (doit être vide)";   pveum user token permissions "$TOFU" "$JETON" --path /pool/prod
echo "== jeton sur /pool/recette";                 pveum user token permissions "$TOFU" "$JETON" --path /pool/recette
echo "== nadia sur /pool/prod";                    pveum user permissions nadia.roussel@pve --path /pool/prod
echo "== nadia sur /nodes/hv01 (lecture seule)";   pveum user permissions nadia.roussel@pve --path /nodes/hv01
