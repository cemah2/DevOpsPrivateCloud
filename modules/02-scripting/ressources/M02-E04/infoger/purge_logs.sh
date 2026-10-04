#!/bin/bash
# purge_logs.sh - InfoGer - v1.3 (2023)
# Purge les journaux applicatifs de plus de N jours.
# Usage : purge_logs.sh <dossier> [jours]
# Lance par cron toutes les nuits sur les serveurs applicatifs.

DIR=$1
DAYS=$2
LOG=/var/log/purge_logs.log

if [ -z $DAYS ]; then
  DAYS=30
fi

echo "`date` debut purge de $DIR ($DAYS jours)" >> $LOG

cd $DIR
nb=0
for f in $(ls *.log *.log.gz 2>/dev/null); do
  age=$(( ( $(date +%s) - $(stat -c %Y $f) ) / 86400 ))
  if [ $age -gt $DAYS ]; then
    rm $f
    nb=`expr $nb + 1`
  fi
done

# les vieux dossiers d'archives aussi
rm -rf $DIR/archives/*

echo "`date` fin purge : $nb fichiers supprimes" >> $LOG
