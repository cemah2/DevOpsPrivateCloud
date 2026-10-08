#!/usr/bin/env bash
# cles-clientes.sh — M08-E13 (SEC-923) : capacités minimales des clients de cephcli01. Depuis adm01.
#   - client.rbd-test (M08-E06) : mêmes profils, restreints à 10.10.30.20/32 (ceph auth caps : la
#     clé ne change pas, le trousseau déjà déposé reste valable) ;
#   - client.rbd-lecture : lecture seule de rbd-test (sauvegardes, M08-E25).
# « ceph auth caps » REMPLACE toutes les capacités : on les répète toutes.
# La clé de rbd-lecture part dans le Vault par outils/ajouter-cle-ceph.sh, puis par le rôle.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
IP_CLIENT=10.10.30.20
POOL=rbd-test
c() { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")"; }

echo "== client.rbd-test : profils rbd sur $POOL, depuis $IP_CLIENT seulement"
c auth caps client.rbd-test \
  mon "profile rbd network $IP_CLIENT/32" \
  osd "profile rbd pool=$POOL network $IP_CLIENT/32" \
  mgr "profile rbd pool=$POOL"
c auth get client.rbd-test | grep -E '^\s*caps'

echo "== client.rbd-lecture : lecture seule de $POOL"
c auth get client.rbd-lecture >/dev/null 2>&1 || c auth get-or-create client.rbd-lecture \
  mon "profile rbd" \
  osd "profile rbd-read-only pool=$POOL" \
  mgr "profile rbd pool=$POOL" >/dev/null
c auth get client.rbd-lecture | grep -E '^\s*caps'

echo "== Inventaire des entités clientes (hors clés de démons)"
c auth ls --format json | jq -r '.auth_dump[] | select(.entity | test("^client\\."))
  | select(.entity | test("^client\\.(rgw|nfs|crash|ceph-exporter|bootstrap-)") | not)
  | "\(.entity)\t\(.caps | to_entries | map("\(.key)=\(.value)") | join(" ; "))"'

cat <<FIN

Suite :
  cd ~/src/ansible && outils/ajouter-cle-ceph.sh client.rbd-lecture
  ceph_client.yml : client.rbd-lecture dans ceph_client_cles ; MR ; playbooks/ceph-clients.yml
  Registre des secrets : client.rbd-test (capacités modifiées), client.rbd-lecture (nouvelle).
FIN
