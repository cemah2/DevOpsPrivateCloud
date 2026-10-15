#!/usr/bin/env bash
# outils/secrets-compose.sh — crée le secret de la pile de test de MédiNotif (M12-E17).
# Ne remplace JAMAIS un secret existant. Dossier secrets/ en 700 (ignoré par Git) : le fichier y est
# lisible (644) par les UID des conteneurs (999 pour rabbitmq, 10002 pour le worker), mais le
# dossier ne laisse entrer que son propriétaire sur l'hôte (même raisonnement qu'en M12-E08).
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
install -d -m 700 secrets
f=secrets/amqp_mdp
if [[ -s "$f" ]]; then
  echo "secret existant conservé : $f"
  exit 0
fi
# Hexadécimal : le mot de passe entre dans une URL (amqp://…) sans échappement.
openssl rand -hex 24 > "$f"
chmod 644 "$f"
echo "secret créé : $f"
