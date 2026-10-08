#!/usr/bin/env bash
# types-volumes.sh — crée (ou vérifie) les types de volumes et la QoS de M10-E11. Idempotent.
# Usage : OS_CLOUD=medisphere-admin outils/types-volumes.sh
set -euo pipefail
: "${OS_CLOUD:?définis OS_CLOUD (ex. medisphere-admin)}"

existe() { openstack "$1" show "${@:2}" >/dev/null 2>&1; }

existe "volume type" ceph-standard || openstack volume type create --public \
  --description "Ceph PAR1, pool volumes (défaut)" \
  --property volume_backend_name=rbd-1 ceph-standard

existe "volume type" ceph-iops-limite || openstack volume type create --public \
  --description "Ceph PAR1, limité à 500 IOPS / 100 Mio/s (recette, tests de charge)" \
  --property volume_backend_name=rbd-1 ceph-iops-limite

existe "volume qos" qos-500iops || openstack volume qos create --consumer front-end \
  --property total_iops_sec=500 --property total_bytes_sec=104857600 qos-500iops

# Association idempotente : on regarde si le type est déjà lié.
if ! openstack volume qos show -f json qos-500iops | jq -e '.associations | tostring | test("ceph-iops-limite")' >/dev/null; then
  openstack volume qos associate qos-500iops ceph-iops-limite
fi

openstack volume type list --long
openstack volume qos show qos-500iops
