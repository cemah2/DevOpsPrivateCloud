#!/bin/bash
# collecte-etc.sh - sauvegarde /etc des VMs du socle (Lucas, v3, "testé sur ma VM")
# usage : ./collecte-etc.sh [debug]
# lancé par cron sur adm01 tous les jours à 2h

DEST=$COLLECTE_DIR
PVE=https://192.168.1.20:8006/api2/json
TOKEN="wb-automation@pve!lab=8c2e4f1a-5b7d-4e3a-9f60-2d1c8b7a6e54"
GARDER=7
DEBUG=$1

if [ $DEBUG == "debug" ]; then
  echo "Appel de l'API avec le jeton $TOKEN"
fi

cd $DEST
JOUR=`date +%Y%m%d`
mkdir $JOUR

# liste des VMs du socle
curl -s -k -H "Authorization: PVEAPIToken=$TOKEN" $PVE/cluster/resources?type=vm > /tmp/vms.json
HOTES=$(cat /tmp/vms.json | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

set -e
OK=0
for h in $HOTES; do
  echo "collecte de $h"
  ssh -o StrictHostKeyChecking=no $h "sudo tar czf - /etc" > $JOUR/$h.tar.gz
  ((OK++))
done

# purge des vieilles collectes
for d in $(ls -t | tail -n +$GARDER); do
  rm -rf $d
done

echo "Terminé : $OK hôtes collectés"
