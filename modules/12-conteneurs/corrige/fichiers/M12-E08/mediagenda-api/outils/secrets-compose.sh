#!/usr/bin/env bash
# outils/secrets-compose.sh — crée les secrets locaux de la pile Compose (M12-E08).
#
# Une seule fois par poste ou VM de recette ; ne remplace jamais un secret existant (le volume
# de PostgreSQL a été initialisé avec lui : le changer demande aussi un ALTER ROLE).
#
# Droits : sans Swarm, Compose MONTE le fichier dans le conteneur (bind mount) avec ses droits
# de l'hôte ; uid/gid/mode de la syntaxe longue ne s'appliquent pas à un secret « file: ».
# L'API tourne sous l'UID 10001 : un fichier en 600 appartenant à admin lui serait illisible.
# On protège donc par le DOSSIER (700, admin seul le traverse sur l'hôte) et on laisse le
# fichier en 644, lisible une fois monté. Voir le corrigé de M12-E08, « Pièges classiques ».
set -euo pipefail
cd "$(dirname "$0")/.."
install -d -m 700 secrets
if [[ -s secrets/db_mdp ]]; then
  echo "secrets/db_mdp existe déjà : conservé."
  exit 0
fi
# Hexadécimal : utilisable tel quel dans une URL postgresql:// (aucun caractère à échapper).
( umask 022; openssl rand -hex 24 > secrets/db_mdp )
chmod 644 secrets/db_mdp
echo "secrets/ (700) et secrets/db_mdp créés."
