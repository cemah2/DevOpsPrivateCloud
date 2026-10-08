#!/usr/bin/env bash
# ceph-conf-clients.sh — produit le ceph.conf minimal des clients OpenStack depuis ceph01 et le
# pose dans etc/kolla/config/{glance,cinder,nova}/ceph.conf (M10-E10).
# Usage : outils/ceph-conf-clients.sh [hôte-ceph]   (depuis la racine de ~/src/openstack)
# Lecture seule côté Ceph. Retire les tabulations de début de ligne (refusées par Kolla).
set -euo pipefail

hote="${1:-ceph01}"
racine="$(git rev-parse --show-toplevel)"
cible="$racine/etc/kolla/config"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# shellcheck disable=SC2029  # la commande est volontairement évaluée sur l'hôte Ceph
ssh -o BatchMode=yes "$hote" 'sudo cephadm shell -- ceph config generate-minimal-conf' 2>/dev/null \
  | sed -e 's/^[[:space:]]\+//' -e '/^#/d' >"$tmp"

grep -q '^fsid = ' "$tmp" || { echo "ceph.conf inattendu (pas de fsid) : vérifie l'accès à $hote" >&2; exit 1; }
grep -q '^mon_host = ' "$tmp" || { echo "ceph.conf inattendu (pas de mon_host)" >&2; exit 1; }

for service in glance cinder nova; do
  install -D -m 0644 "$tmp" "$cible/$service/ceph.conf"
  echo "écrit : etc/kolla/config/$service/ceph.conf"
done
