# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M12-E37 « Panne : l'application ne joint plus sa base » : l'API de recette résout et
# joint base-recette:5432 et valkey:6379, elle est sur le réseau des données, aucun filtrage de l'hôte
# ne coupe le trafic vers la base, /pret répond 200. Lecture seule (docker exec d'un test de
# connexion en Python dans le conteneur de l'API).

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E37 — L'API joint sa base et son cache"
require_cmd jq curl ssh

if _m12x_recette_repond; then
  check_cmd "API : conteneur démarré et sain" _m12x_sain api
  check_cmd "API : rattachée au réseau des données (recette_donnees)" \
    _m12x_jq '.services.api.reseaux | index("recette_donnees")'
  check_cmd "base : rattachée au même réseau que l'API" \
    _m12x_jq '(.services.db.reseaux - (.services.db.reseaux - .services.api.reseaux)) | length > 0'
  check_cmd "API : le nom base-recette se résout" \
    _m12x_dans_api "import socket; socket.getaddrinfo('base-recette', 5432)"
  check_cmd "API : connexion TCP à base-recette:5432 en moins de 3 s" \
    _m12x_dans_api "import socket; socket.create_connection(('base-recette', 5432), 3).close()"
  check_cmd "API : connexion TCP à valkey:6379 en moins de 3 s" \
    _m12x_dans_api "import socket; socket.create_connection(('valkey', 6379), 3).close()"
  check_cmd "hôte : aucune règle nftables (famille bridge) ne jette le trafic vers PostgreSQL" \
    _m12x_jq '.nft_bridge_5432 == false'
else
  skip "réseau de la recette" "Docker ne répond pas sur $_m12x_ctr01, ou la pile « recette » n'existe pas"
fi
check_http "API : /pret répond 200" "$_m12x_url_api/pret" 200 --max-time 10
check_cmd "panne M12-E37 close (lab/bin/break 12 37 --annuler après réparation)" _m12x_aucune_panne_active E37
