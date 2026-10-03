#!/usr/bin/env bash
# configurer-client.sh — Configure chrony en client du lab (M00-E31).
# Usage (root) : configurer-client.sh <SERVEUR-NTP>
#   adm01 : 10.10.10.1   dns01 : 10.10.20.1   pbs01 : 10.10.10.1
set -euo pipefail

serveur="${1:?Usage : $0 <SERVEUR-NTP>}"

# chrony entre en conflit avec systemd-timesyncd : apt retire ce dernier.
if ! command -v chronyd >/dev/null 2>&1; then
  apt-get update -q
  apt-get install -y chrony
fi

# Neutralise les sources Internet par défaut (copie de sauvegarde conservée)
cp -n /etc/chrony/chrony.conf /etc/chrony/chrony.conf.orig
sed -i -E 's/^(pool|server) /# &/' /etc/chrony/chrony.conf
# Sources fournies par DHCP : inutiles ici (adresses statiques)
sed -i -E 's|^(sourcedir /run/chrony-dhcp)|# \1|' /etc/chrony/chrony.conf

mkdir -p /etc/chrony/sources.d
printf 'server %s iburst\n' "$serveur" > /etc/chrony/sources.d/lab.sources

systemctl restart chrony
sleep 5
chronyc -n sources -v
chronyc -n tracking
