#!/usr/bin/env bash
# ec.sh — M08-E15 (PLAT-925) : profil EC 2+1 sur HDD par baie, pool de données RBD, image d'essai.
# Depuis adm01. Idempotent. FastEC (allow_ec_optimizations) : activé par le corrigé (irréversible,
# exige que tous les OSD soient en Tentacle) — mets OPTIM=non pour ne pas l'activer.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
OPTIM=${OPTIM:-oui}
c()   { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")" 2>/dev/null; }
rbd() { ssh -o BatchMode=yes "$ADMIN" "sudo rbd $(printf '%q ' "$@")" 2>/dev/null; }

echo "== Profil ec-21-hdd"
c osd erasure-code-profile ls | grep -qx ec-21-hdd \
  || c osd erasure-code-profile set ec-21-hdd k=2 m=1 crush-device-class=hdd crush-failure-domain=rack
c osd erasure-code-profile get ec-21-hdd

echo "== Pool rbd-ec-donnees"
c osd pool ls | grep -qx rbd-ec-donnees || c osd pool create rbd-ec-donnees erasure ec-21-hdd
c osd pool set rbd-ec-donnees allow_ec_overwrites true
[[ "$OPTIM" == oui ]] && c osd pool set rbd-ec-donnees allow_ec_optimizations true
c osd pool application enable rbd-ec-donnees rbd
echo "min_size : $(c osd pool get rbd-ec-donnees min_size)"

echo "== Image rbd-test/archives-ec (métadonnées dans rbd-test, données dans rbd-ec-donnees)"
rbd info rbd-test/archives-ec >/dev/null || rbd create rbd-test/archives-ec --size 10G --data-pool rbd-ec-donnees
rbd info rbd-test/archives-ec | grep -E 'size|data_pool|features'

echo "== Droits du client de cephcli01 sur le pool de données (toutes les capacités répétées)"
c auth caps client.rbd-test \
  mon 'profile rbd network 10.10.30.20/32' \
  osd 'profile rbd pool=rbd-test network 10.10.30.20/32, profile rbd pool=rbd-ec-donnees network 10.10.30.20/32' \
  mgr 'profile rbd pool=rbd-test, profile rbd pool=rbd-ec-donnees'
