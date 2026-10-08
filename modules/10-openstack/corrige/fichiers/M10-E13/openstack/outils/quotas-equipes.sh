#!/usr/bin/env bash
# quotas-equipes.sh — pose les quotas de docs/cloud/capacite.md (M10-E13). Idempotent.
# À partir de M10-E15, les quotas sont tenus par OpenTofu (envs/openstack-projets) : ce script
# ne sert plus qu'à l'amorçage d'un nouveau cloud ou à la comparaison.
# Usage : OS_CLOUD=medisphere-admin outils/quotas-equipes.sh
set -euo pipefail
: "${OS_CLOUD:?définis OS_CLOUD (ex. medisphere-admin)}"

# projet : instances cores ram volumes gigabytes snapshots backups backup-gigabytes floating-ips networks subnets routers secgroups secgroup-rules ports
declare -A QUOTAS=(
  [plateforme]="4 4 2048 10 100 10 10 100 2 2 2 1 10 100 30"
  [mediagenda-dev]="4 5 3072 10 100 10 10 100 3 2 2 1 10 100 30"
  [mediagenda-prod]="4 8 6144 10 200 20 20 400 3 2 2 1 10 100 30"
)

for projet in "${!QUOTAS[@]}"; do
  read -r inst cores ram vols go snaps sauv sauvgo fip nets subnets routeurs sg sgr ports <<<"${QUOTAS[$projet]}"
  id="$(openstack project show -f value -c id --domain medisphere "$projet")"
  openstack quota set \
    --instances "$inst" --cores "$cores" --ram "$ram" \
    --volumes "$vols" --gigabytes "$go" --snapshots "$snaps" \
    --backups "$sauv" --backup-gigabytes "$sauvgo" \
    --floating-ips "$fip" --networks "$nets" --subnets "$subnets" --routers "$routeurs" \
    --secgroups "$sg" --secgroup-rules "$sgr" --ports "$ports" \
    "$id"
  echo "== $projet"
  openstack quota show --usage "$id"
done
