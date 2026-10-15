#!/usr/bin/env bash
# creer-secrets.sh — secrets Podman de la pile MédiAgenda de ctr02 (compte app), M12-E14.
#   app@ctr02:~/m12/e14$ ./creer-secrets.sh
# Le mot de passe est tiré au hasard, ne passe ni par l'écran, ni par un fichier, ni par la ligne
# de commande d'un processus : il va directement dans le magasin de secrets de Podman (pilote
# « file » par défaut : ~/.local/share/containers/storage/secrets/, accessible au seul compte app).
# Deux secrets, car l'application ne lit qu'une URL complète (MEDIAGENDA_DB_URL), qui CONTIENT le
# mot de passe. Ne remplace jamais un secret existant (la base a déjà ce mot de passe).
set -euo pipefail

if podman secret exists mediagenda-pg-mdp; then
  echo "secrets déjà présents : rien à faire (rotation : voir le corrigé de M12-E14)"
  exit 0
fi
mdp="$(openssl rand -hex 24)"
printf '%s' "$mdp" | podman secret create mediagenda-pg-mdp - >/dev/null
printf 'postgresql://mediagenda:%s@mediagenda-pg:5432/mediagenda' "$mdp" \
  | podman secret create mediagenda-db-url - >/dev/null
unset mdp
podman secret ls --format '{{.Name}} {{.Driver}} {{.CreatedAt}}'
