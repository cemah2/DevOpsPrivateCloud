#!/usr/bin/env bash
# sauvegarde_config.sh — copie des fichiers de configuration d'un serveur distant.
# Version corrigée (M02-E04) du script InfoGér v0.9.
# Usage : sauvegarde_config.sh SERVEUR FICHIER...
set -euo pipefail

(($# >= 2)) || {
  echo "Usage : ${0##*/} SERVEUR FICHIER..." >&2
  exit 2
}
serveur="$1"
shift
fichiers=("$@")
dest="/srv/sauvegardes/${serveur}/$(date +%F)"
tmp="$(mktemp -d)"
# Apostrophes : $tmp est lu au moment du signal, pas au moment du trap.
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p -- "$dest"
for fichier in "${fichiers[@]}"; do
  if [[ "$fichier" != /* ]]; then
    echo "chemin non absolu ignoré : $fichier" >&2
    continue
  fi
  # scp -- : un nom qui commence par « - » n'est pas pris pour une option.
  scp -q -- "${serveur}:${fichier}" "$tmp/"
done

# Le $(hostname) doit être évalué sur le serveur distant : il est protégé.
# shellcheck disable=SC2016  # expansion voulue côté distant
ssh -- "$serveur" 'tar -czf "/tmp/etc-$(hostname).tgz" /etc && echo "archive faite sur $(hostname)"'

cp -- "$tmp"/* "$dest/"
# sudo ne s'applique pas à la redirection : c'est tee qui écrit avec les droits.
echo "dernière sauvegarde : $(date -Is)" | sudo tee /srv/sauvegardes/ETAT >/dev/null

printf 'Sauvegarde de %s terminée à 100%%\n' "$serveur"
