#!/usr/bin/env bash
# pve-terratest-compte.sh — identité Proxmox DÉDIÉE aux tests Terratest (M29-E08, PLAT-3008).
# À lancer en root sur pve01. Rejouable (ce qui existe n'est pas recréé, les ACL sont reposées).
# Modèle : pve-tofu-compte.sh (M05-E03). Le secret du jeton n'est affiché qu'à sa création :
# copie-le aussitôt dans ~/.config/workbook/pve-terratest.env (600) sur adm01, et dans la variable
# protégée et masquée PROXMOX_VE_API_TOKEN de plateforme/tofu-modules.
#
# Pourquoi pas wb-tofu@pve!tofu : son rôle WBTofu est posé sur /pool/lab, donc sur TOUTES les VMs
# du lab (socle compris). Un test qui se trompe de VMID, un module qui détruit plus qu'il ne crée
# (c'est justement ce qu'on teste) ou un jeton de CI volé ne doivent pouvoir toucher QUE les VMs
# de test.
#
# Pourquoi un SOUS-POOL lab/terratest (pools imbriqués, Proxmox VE ≥ 8.1) et pas des ACL par VMID
# (/vms/2290…) : détruire une VM SUPPRIME les ACL de son chemin /vms/<vmid> (remove_vm_access, appelé
# à chaque DELETE …/qemu/<vmid>) ; après le premier test, le jeton n'aurait plus aucun droit. Le
# sous-pool, lui, survit aux VMs : le clonage avec « pool=lab/terratest » exige VM.Allocate sur
# /pool/lab/terratest (API de qemu-server, POST …/clone), et la VM créée hérite des droits du pool.
# Le sous-pool reste DANS lab : les droits de wb-tofu (ACL propagée sur /pool/lab) s'y appliquent,
# les VMs de test restent dans le périmètre du lab.
#   - lire et cloner un modèle exige VM.Audit + VM.Clone sur /vms/{modèle} : on les donne sur la
#     plage des modèles Debian dorés (9010-9029, PLAN §4.8) et SEULEMENT là (VM.Clone sur
#     /pool/lab permettrait de copier le disque de n'importe quelle VM du lab, coffre compris).
#     Un modèle détruit puis recréé au même VMID perd son ACL : relancer ce script après Packer.
#
# Variables facultatives : ZONE_SDN (lab), VNET (vsandbox), STOCKAGE (local-nvme),
#   POOL (lab/terratest), VMID_MODELES ("9010 9029"), EXPIRATION_JOURS (90), JETON (terratest).
set -euo pipefail

ZONE_SDN="${ZONE_SDN:-lab}"
VNET="${VNET:-vsandbox}"
STOCKAGE="${STOCKAGE:-local-nvme}"
POOL="${POOL:-lab/terratest}"
read -r MODELE_DEBUT MODELE_FIN <<<"${VMID_MODELES:-9010 9029}"
# 90 jours : un jeton de test sert peu ; il se renouvelle à la revue trimestrielle des accès.
EXPIRATION_JOURS="${EXPIRATION_JOURS:-90}"
UTILISATEUR="wb-terratest@pve"
JETON="${JETON:-terratest}"

# Sur les VMs de test : créer (clone), configurer, démarrer, lire l'agent, détruire.
PRIVS_TESTS=(
  VM.Audit            # lire config et état, /cluster/resources
  VM.Allocate         # créer (cible du clone) et détruire la VM
  VM.Config.CPU
  VM.Config.Memory
  VM.Config.Disk      # agrandir le disque cloné, lecteur cloud-init
  VM.Config.CDROM     # le lecteur cloud-init est un média « cdrom »
  VM.Config.Network
  VM.Config.HWType
  VM.Config.Options   # nom, description, étiquettes, agent
  VM.Config.Cloudinit
  VM.PowerMgmt        # démarrer, arrêter avant destruction
  VM.GuestAgent.Audit # adresses annoncées par l'agent QEMU (vérification du test)
  Pool.Audit          # lire l'appartenance au pool (relecture du fournisseur)
)
# Sur les modèles : les voir (source de données du module) et les cloner. Rien d'autre.
PRIVS_MODELES=(VM.Audit VM.Clone)

existe() { pvesh get "$1" >/dev/null 2>&1; }

role() { # role NOM PRIVILÈGES…
  local nom="$1"
  shift
  if existe "/access/roles/$nom"; then
    pveum role modify "$nom" --privs "$*"
  else
    pveum role add "$nom" --privs "$*"
  fi
}
role WBTerratest "${PRIVS_TESTS[@]}"
role WBTerratestModele "${PRIVS_MODELES[@]}"

existe "/access/users/$UTILISATEUR" \
  || pveum user add "$UTILISATEUR" --comment "Tests Terratest de plateforme/tofu-modules (PLAT-3008)"
if existe "/access/users/$UTILISATEUR/token/$JETON"; then
  echo "jeton $UTILISATEUR!$JETON déjà présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-terratest.env sur adm01."
  pveum user token add "$UTILISATEUR" "$JETON" --privsep 1 \
    --expire "$(date -d "+${EXPIRATION_JOURS} days" +%s)" --comment "Terratest, plateforme/tofu-modules (PLAT-3008)"
fi

acl() { # acl CHEMIN RÔLE : utilisateur ET jeton (privsep : le jeton n'a que l'intersection)
  pveum acl modify "$1" --users "$UTILISATEUR" --roles "$2"
  pveum acl modify "$1" --tokens "$UTILISATEUR!$JETON" --roles "$2"
}

# Sous-pool des VMs de test (dans lab). La plage 2290-2299 est imposée par le CODE du test (variable
# validée de la configuration, choix d'un VMID libre), pas par Proxmox.
# Un identifiant de pool imbriqué contient « / » : « pvesh get /pools/lab/terratest » ne désigne pas ce
# pool (l'API /pools/{poolid} est dépréciée depuis 8.1) ; on cherche dans la liste des pools.
# (Sortie JSON compacte de pvesh : « "poolid":"lab/terratest" ».)
pool_existe() { pvesh get /pools --output-format json | grep -qF "\"poolid\":\"$1\""; }
pool_existe "$POOL" || pveum pool add "$POOL" --comment "VMs jetables de Terratest (M29-E08) — RB-293"
acl "/pool/$POOL" WBTerratest
for ((v = MODELE_DEBUT; v <= MODELE_FIN; v++)); do
  acl "/vms/$v" WBTerratestModele
done
existe "/storage/$STOCKAGE" || { echo "stockage inconnu : $STOCKAGE" >&2; exit 1; }
acl "/storage/$STOCKAGE" PVEDatastoreUser # Datastore.AllocateSpace + Datastore.Audit
existe "/cluster/sdn/vnets/$VNET" || { echo "VNet inconnu : $VNET" >&2; exit 1; }
acl "/sdn/zones/$ZONE_SDN/$VNET" PVESDNUser # SDN.Use

# --- Contrôle des droits effectifs du JETON -----------------------------------------------------
# Attendu : rien sur « / », rien sur /pool/lab, WBTerratest sur /pool/lab/terratest, VM.Audit et
# VM.Clone sur un modèle, rien sur /vms/1004 (git01).
for chemin in / /pool/lab "/pool/$POOL" "/vms/$MODELE_DEBUT" /vms/1004 "/storage/$STOCKAGE"; do
  echo "== droits effectifs du jeton sur $chemin"
  pveum user token permissions "$UTILISATEUR" "$JETON" --path "$chemin"
done
