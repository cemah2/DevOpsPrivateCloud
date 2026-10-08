#!/usr/bin/env bash
# pbs-stockage.sh — stockage pbs-par2 chiffré et tâche hv-nuit du cluster hv-par1 (M09-E15). Rejouable.
#
# À lancer en root sur hv01 (storage.cfg et vzdump.cron sont communs au cluster).
# Le secret du jeton est lu SANS ÉCHO : il n'apparaît ni à l'écran ni dans l'historique. Il passe
# en argument de pvesm, donc reste visible dans « ps » le temps de l'appel (même compromis qu'au
# M00-E22) ; pvesm le range ensuite dans /etc/pve/priv/storage/<STOCKAGE>.pw (root seul).
#   EMPREINTE=<empreinte SHA-256 de pbs01> ./pbs-stockage.sh
set -euo pipefail

STOCKAGE=pbs-par2
SERVEUR=10.20.10.10
STORE=ds-lab
NS=par1/hv
JETON_ID='wb-hv@pbs!hv-par1'
EMPREINTE="${EMPREINTE:?donne l\'empreinte : EMPREINTE=aa:bb:… $0}"

if pvesm status --storage "$STOCKAGE" >/dev/null 2>&1; then
  echo "== stockage $STOCKAGE présent"
else
  read -rsp "Secret du jeton $JETON_ID : " secret
  echo
  [[ -n "$secret" ]] || { echo "secret vide" >&2; exit 1; }
  # --encryption-key autogen : clé AES-256 générée sur place, sans phrase de passe, rangée dans
  # /etc/pve/priv/storage/$STOCKAGE.enc (root seul, répliquée sur les nœuds par pmxcfs).
  pvesm add pbs "$STOCKAGE" --server "$SERVEUR" --datastore "$STORE" --namespace "$NS" \
    --username "$JETON_ID" --password "$secret" --fingerprint "$EMPREINTE" \
    --encryption-key autogen --content backup --prune-backups keep-all=1
  unset secret
fi
pvesm status --storage "$STOCKAGE"
ls -l "/etc/pve/priv/storage/$STOCKAGE.pw" "/etc/pve/priv/storage/$STOCKAGE.enc"

# --- Tâche de sauvegarde du cluster ----------------------------------------------------------------
if pvesh get /cluster/backup/hv-nuit >/dev/null 2>&1; then
  pvesh set /cluster/backup/hv-nuit --schedule '03:15' --storage "$STOCKAGE" --all 1 --mode snapshot \
    --prune-backups keep-all=1 --enabled 1
else
  pvesh create /cluster/backup --id hv-nuit --schedule '03:15' --storage "$STOCKAGE" --all 1 \
    --mode snapshot --prune-backups keep-all=1 --enabled 1 --notes-template '{{guestname}}' \
    --comment "Toutes les VMs de hv-par1 vers PAR2, chiffré (PLAT-1025)"
fi
pvesh get /cluster/backup/hv-nuit --output-format json-pretty
