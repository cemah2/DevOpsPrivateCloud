#!/usr/bin/env bash
# replication.sh — VM rep01 (110) sur zfs-local et ses deux tâches de réplication (M09-E14). Rejouable.
#
# À lancer en root sur hv01. Le template 199 est sur ceph-vm (M09-E11) : le clone complet pose le
# disque de 110 sur zfs-local (storage=) ; le pool ZFS « tank » et le stockage « zfs-local »
# existent à l'identique sur les trois nœuds (M09-E06), condition de la réplication.
set -euo pipefail

VMID=110
NOM=rep01
SOURCE=hv01
CIBLES=(hv02 hv03)
HORAIRE='*/10'
DEBIT=20 # Mo/s

[[ "$(hostname -s)" == "$SOURCE" ]] || { echo "à lancer sur $SOURCE" >&2; exit 1; }
pvesm status --storage zfs-local | grep -q active || { echo "zfs-local inactif sur $SOURCE" >&2; exit 1; }

if ! qm status "$VMID" >/dev/null 2>&1; then
  qm clone 199 "$VMID" --name "$NOM" --full 1 --storage zfs-local --target "$SOURCE"
  qm set "$VMID" --memory 1024 --cores 1 --tags "env-m09;replication" --description "Réplication ZFS (PLAT-1024)"
  qm start "$VMID"
fi
qm config "$VMID" | grep -E '^scsi0:' | grep -q 'zfs-local:' || { echo "disque de $VMID hors de zfs-local" >&2; exit 1; }
zfs list -H -o name "tank/vm-$VMID-disk-0" >/dev/null # le zvol existe (sinon : erreur ici)

n=0
for cible in "${CIBLES[@]}"; do
  id="$VMID-$n"
  if pvesr read "$id" >/dev/null 2>&1; then
    echo "== tâche $id déjà présente"
  else
    pvesr create-local-job "$id" "$cible" --schedule "$HORAIRE" --rate "$DEBIT" \
      --comment "$NOM vers $cible (PLAT-1024)"
  fi
  pvesr schedule-now "$id"
  n=$((n + 1))
done

echo "== /etc/pve/replication.cfg"; cat /etc/pve/replication.cfg
echo "== état (la première synchronisation copie tout le disque : quelques minutes)"
pvesr status
