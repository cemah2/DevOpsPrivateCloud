#!/usr/bin/env bash
# outils/maj-progressive.sh — met à jour l'API de la recette INSTANCE PAR INSTANCE (M12-E30).
#
#   admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=0.3.0 outils/maj-progressive.sh
#
# Pour chaque instance (api, puis api-b) :
#   1. recrée le conteneur avec la nouvelle image et ATTEND qu'il soit « healthy » (up --wait) ;
#   2. attend que HAProxy le voie UP (page d'état CSV, champ status) avant de passer à la suivante :
#      sans cette attente, les deux instances pourraient être hors rotation en même temps ;
#   3. en cas d'échec, s'arrête AVANT de toucher la suivante (l'autre instance sert toujours) et
#      rappelle comment revenir à la version précédente.
# Code retour : 0 succès, 1 échec d'une instance, 2 usage.
set -euo pipefail
cd "$(dirname "$0")/.."
export COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml:compose.ha.yaml}"
: "${MEDIAGENDA_TAG:?MEDIAGENDA_TAG (version cible) obligatoire}"
ETAT_URL="${ETAT_URL:-http://127.0.0.1:8404/etat;csv}"
DELAI_UP="${DELAI_UP:-60}"

# serveur_up NOM — le serveur NOM du backend « api » est UP pour HAProxy.
serveur_up() {
  curl -fsS --max-time 3 "$ETAT_URL" 2>/dev/null \
    | awk -F, -v s="$1" '$1 == "api" && $2 == s { print $18 }' | grep -q '^UP'
}

precedente="$(docker compose images api --format json 2>/dev/null | jq -r '.[0].Tag // empty' || true)"
echo "Version en service : ${precedente:-inconnue} ; cible : $MEDIAGENDA_TAG"
for paire in api:api-a api-b:api-b; do
  service="${paire%%:*}"
  serveur="${paire##*:}"
  echo "== $service : recréation"
  if ! docker compose up -d --no-deps --wait --wait-timeout 90 "$service"; then
    echo "ÉCHEC : $service n'est pas devenu healthy. L'autre instance sert toujours." >&2
    echo "Retour arrière : MEDIAGENDA_TAG=${precedente:-<PRÉCÉDENTE>} $0" >&2
    exit 1
  fi
  echo "== $service : attente du passage UP dans HAProxy ($serveur)"
  for ((i = 0; i < DELAI_UP; i++)); do
    serveur_up "$serveur" && break
    sleep 1
  done
  if ! serveur_up "$serveur"; then
    echo "ÉCHEC : HAProxy ne voit pas $serveur UP après ${DELAI_UP} s (/pret ?)." >&2
    echo "Retour arrière : MEDIAGENDA_TAG=${precedente:-<PRÉCÉDENTE>} $0" >&2
    exit 1
  fi
done
echo "Mise à jour terminée : les deux instances sont en $MEDIAGENDA_TAG."
