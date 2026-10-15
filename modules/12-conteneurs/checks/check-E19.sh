# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués à distance
#
# check-E19.sh — M12-E19 : Conteneuriser Legacy-RDV
# À lancer depuis adm01. Lecture seule : API GitLab en GET ; docker inspect, docker logs et requête
# SQL de comptage (SELECT) dans MariaDB sur ctr01 ; HTTP vers l'application.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E19 — Conteneuriser Legacy-RDV"
require_cmd jq curl

# --- 1. Le projet ----------------------------------------------------------------------------------------------
check_output "GitLab : projet legacy/legacy-rdv, branche par défaut main" '"default_branch": *"main"' \
  bash -c 'jq "{default_branch}" <<<"$1"' _ "$(_m12o_projet legacy/legacy-rdv)"
for _m12o_e19_f in Dockerfile .dockerignore compose.yaml; do
  check_cmd "legacy/legacy-rdv (main) : $_m12o_e19_f" test -n "$(_m12o_fichier legacy/legacy-rdv "$_m12o_e19_f")"
done
_m12o_e19_arbre="$(gitlab_api "projects/legacy%2Flegacy-rdv/repository/tree?ref=main&per_page=100" 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
check_cmd "legacy/legacy-rdv (main) : une page de sonde ajoutée (sante*.php, health*.php…)" \
  _m12o_correspond "$_m12o_e19_arbre" '^(sante|health|vivacite|ping)[a-z_-]*\.php$'
_m12o_e19_conf="$(_m12o_fichier legacy/legacy-rdv config.php)"
check_cmd "config.php (main) : lit l'environnement, sans le mot de passe d'InfoGér" \
  bash -c 'grep -q "getenv" <<<"$1" && ! grep -q "InfoGer2014" <<<"$1"' _ "$_m12o_e19_conf"

# --- 2. La pile de recette ------------------------------------------------------------------------------------------
_m12o_e19_svc() {
  local id
  id="$(_m12o_docker "ps -aq --filter label=com.docker.compose.project=legacy-rdv --filter label=com.docker.compose.service=$1" | head -n 1)"
  [[ -n "$id" ]] && _m12o_docker "inspect $id" | jq -c '.[0]' 2>/dev/null || true
}
_m12o_e19_web="$(_m12o_e19_svc web)"
_m12o_e19_db="$(_m12o_e19_svc mariadb)"
check_cmd "pile legacy-rdv : application en marche et saine" _m12o_json "${_m12o_e19_web:-}" '.State.Status == "running" and .State.Health.Status == "healthy"'
check_cmd "pile legacy-rdv : MariaDB 11.8 en marche et saine" _m12o_json "${_m12o_e19_db:-}" \
  '.State.Status == "running" and .State.Health.Status == "healthy" and (.Config.Image | test("mariadb:11\\.8"))'
check_cmd "MariaDB : aucun port publié sur l'hôte" _m12o_json "${_m12o_e19_db:-}" \
  '[.NetworkSettings.Ports // {} | to_entries[] | .value // [] | .[]] | length == 0'
check_output "Depuis adm01 : Legacy-RDV répond sur ctr01:8090" '<title>.*RDV' \
  curl -s --max-time "${WB_TIMEOUT:-5}" "http://$_M12O_NOM01:8090/"
check_cmd "application : compte non root, port 8080 dans le conteneur" _m12o_json "${_m12o_e19_web:-}" \
  '((.Config.User // "") | test("^(0|root)?(:.*)?$") | not) and ((.NetworkSettings.Ports // {}) | has("8080/tcp"))'
check_cmd "application : pièces jointes et sessions sur des volumes nommés" _m12o_json "${_m12o_e19_web:-}" \
  '([.Mounts[] | select(.Type == "volume") | .Destination] | (index("/var/www/legacy-rdv/uploads") != null) and (index("/var/lib/php/sessions") != null))'
_m12o_e19_envs="$(printf '%s\n%s' "$(jq -c '.Config.Env' <<<"${_m12o_e19_web:-null}" 2>/dev/null)" "$(jq -c '.Config.Env' <<<"${_m12o_e19_db:-null}" 2>/dev/null)")"
check_cmd "pile legacy-rdv : aucun mot de passe dans l'environnement des conteneurs" \
  bash -c '[[ "$1" == *"["* ]] && ! grep -Eq "\"(LEGACY_RDV_DB_PASS|MARIADB_PASSWORD|MARIADB_ROOT_PASSWORD|MYSQL_PASSWORD|MYSQL_ROOT_PASSWORD)=" <<<"$1" && ! grep -q "InfoGer2014" <<<"$1"' _ "$_m12o_e19_envs"
_m12o_e19_id="$(jq -r '.Id // empty' <<<"${_m12o_e19_web:-null}" 2>/dev/null || true)"
_m12o_e19_logs() { [[ -n "$_m12o_e19_id" ]] && [[ -n "$(_m12o_docker "logs --tail 5 $_m12o_e19_id" 2>&1)" ]]; }
check_cmd "application : journaux sur les sorties du conteneur (docker logs non vide)" _m12o_e19_logs

# --- 3. Les données migrées ------------------------------------------------------------------------------------------
_m12o_e19_db_id="$(jq -r '.Id // empty' <<<"${_m12o_e19_db:-null}" 2>/dev/null || true)"
# _m12o_e19_sql "REQUÊTE" — requête de LECTURE dans la base de recette ; le mot de passe est lu dans
# le conteneur (secret de la pile), il ne transite pas. Pas d'apostrophe dans la requête (elle est
# déjà entre apostrophes) : « Migration » est écrit en hexadécimal (0x4D69…).
_m12o_e19_sql() {
  [[ -n "$_m12o_e19_db_id" ]] || return 0
  remote "$_M12O_CTR01" "docker exec $_m12o_e19_db_id sh -c 'mariadb -N -u root -p\"\$(cat /run/secrets/legacy_rdv_db_root 2>/dev/null || cat \"\$MARIADB_ROOT_PASSWORD_FILE\")\" -e \"$1\"'" 2>/dev/null || true
}
_m12o_e19_temoin="$(_m12o_e19_sql "SELECT id FROM legacy_rdv.rendez_vous WHERE LOCATE(0x4D6967726174696F6E, patient) > 0 AND piece_jointe IS NOT NULL ORDER BY id DESC LIMIT 1")"
check_cmd "MariaDB de recette : le rendez-vous « Témoin Migration » de legacy01, avec pièce jointe, est migré" \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]]' _ "$_m12o_e19_temoin"
_m12o_e19_piece() {
  [[ "$_m12o_e19_temoin" =~ ^[0-9]+$ ]] || return 1
  local r
  r="$(curl -s -o /dev/null -w '%{http_code} %{size_download}' --max-time "${WB_TIMEOUT:-5}" "http://$_M12O_NOM01:8090/piece.php?id=$_m12o_e19_temoin")"
  [[ "$r" =~ ^200\ [1-9][0-9]*$ ]]
}
check_cmd "Depuis adm01 : la pièce jointe migrée se télécharge (piece.php)" _m12o_e19_piece
check_cmd "plateforme/medisphere (main) : docs/conteneurs/legacy-rdv-12-facteurs.md" \
  bash -c 'grep -Eiq "facteur|12" <<<"$1" && grep -Eiq "écart|ecart" <<<"$1"' _ "$(_m12o_fichier plateforme/medisphere docs/conteneurs/legacy-rdv-12-facteurs.md)"
