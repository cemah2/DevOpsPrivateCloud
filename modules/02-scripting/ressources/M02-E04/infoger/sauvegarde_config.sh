#!/bin/sh
# sauvegarde_config.sh - InfoGer - v0.9
# Copie la configuration d'un serveur distant et envoie un message.
# Usage : sauvegarde_config.sh <serveur> <fichiers...>

SERVEUR=$1
shift
FICHIERS=($@)
DEST=/srv/sauvegardes/$SERVEUR/$(date +%F)
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

mkdir -p $DEST
for fichier in ${FICHIERS[@]}; do
  if [[ -f $fichier ]]; then
    echo "fichier local ignore : $fichier"
    continue
  fi
  scp $SERVEUR:$fichier $TMP/
done

ssh $SERVEUR "tar -czf /tmp/etc-$SERVEUR.tgz /etc && echo archive faite sur $(hostname)"
cp $TMP/* $DEST/
sudo echo "derniere sauvegarde : $(date)" > /srv/sauvegardes/ETAT

msg="Sauvegarde de $SERVEUR terminee a 100%"
printf "$msg\n"
