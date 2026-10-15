#!/usr/bin/env bash
# outils/secrets-compose.sh — crée les secrets de la pile de recette de Legacy-RDV (M12-E19).
# HORS du dépôt : ~/.config/legacy-rdv/ (dossier 700). Fichiers 644 : lus dans les conteneurs par
# www-data (33) et mysql (999), qui ne sont pas propriétaires ; c'est le DOSSIER (700) qui en
# interdit l'accès aux autres comptes de l'hôte. Ne remplace jamais un secret existant.
set -euo pipefail
d="${HOME}/.config/legacy-rdv"
umask 077
install -d -m 700 "$d"
for s in db-mdp db-root; do
  if [[ -s "$d/$s" ]]; then
    echo "secret existant conservé : $d/$s"
  else
    openssl rand -hex 24 > "$d/$s"
    echo "secret créé : $d/$s"
  fi
  chmod 644 "$d/$s"
done
