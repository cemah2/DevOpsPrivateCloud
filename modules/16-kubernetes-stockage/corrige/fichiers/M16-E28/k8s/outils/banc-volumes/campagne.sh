#!/usr/bin/env bash
# plateforme/k8s — outils/banc-volumes/campagne.sh (M16-E28)
# Campagne complète : 4 profils × cibles × 3 répétitions, une mesure à la fois.
# Usage : campagne.sh [CIBLE...]   (défaut : ceph-rbd ceph-rbd-chiffre cephfs emptydir)
set -euo pipefail
ici="$(dirname "$(readlink -f "$0")")"
cibles=("$@")
((${#cibles[@]} > 0)) || cibles=(ceph-rbd ceph-rbd-chiffre cephfs emptydir)
for c in "${cibles[@]}"; do
  for p in wal oltp iops debit; do
    for r in 1 2 3; do
      "$ici/banc-volumes.sh" --cible "$c" --profil "$p" --repetition "$r"
    done
  done
done | tee "$HOME/m16/e28/campagne-$(date +%Y%m%d-%H%M).tsv"
