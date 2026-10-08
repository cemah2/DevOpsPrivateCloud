#!/usr/bin/env bash
# pools.sh — pools du cluster ceph-par2 (Lucas). À lancer dans « cephadm shell ».

ceph osd pool create sauvegardes 32 32 replicated par2-ssd
ceph osd pool set sauvegardes size 2
ceph osd pool set sauvegardes min_size 1
ceph osd pool application enable sauvegardes rbd

ceph osd erasure-code-profile set ec-par2 k=2 m=1 crush-failure-domain=osd
ceph osd pool create archives 32 32 erasure ec-par2
ceph osd pool set archives allow_ec_overwrites true

ceph fs volume create cephfs
ceph osd pool set cephfs.cephfs.meta crush_rule par2-meta

ceph osd pool set noautoscale
ceph osd set-nearfull-ratio 0.95
ceph osd set-full-ratio 0.97

# clé de démo pour le S3 (utilisateur classique, pas besoin de compte)
radosgw-admin user create --uid=demo --display-name="Démo" --access-key=DEMODEMODEMODEMO --secret=demo1234 --admin
