# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués par docker ou bash -c
#
# check-E05.sh — M12-E05 : Un premier Dockerfile pour MédiAgenda
# À lancer depuis adm01. Lecture seule : API GitLab en GET, docker image inspect et docker inspect
# sur ctr01 (SSH), requête HTTP vers le conteneur publié.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E05 — Un premier Dockerfile pour MédiAgenda"
require_cmd jq curl

# --- 1. Le projet GitLab ---------------------------------------------------------------------------
# _m12d_e05_branche — branche par défaut du projet mediagenda/api (vide s'il n'existe pas).
_m12d_e05_branche() {
  gitlab_api "projects/mediagenda%2Fapi" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null || true
}
check_output "GitLab : projet mediagenda/api, branche par défaut main" '^main$' _m12d_e05_branche
for _m12d_e05_f in pyproject.toml uv.lock src/mediagenda/app.py migrations/V1__init.sql Dockerfile .dockerignore; do
  check_cmd "mediagenda/api (main) : $_m12d_e05_f" _m12d_fichier_main mediagenda/api "$_m12d_e05_f"
done

_m12d_e05_df="$(_m12d_contenu_main mediagenda/api Dockerfile)"
check_cmd "Dockerfile : FROM docker.io/library/python:3.13-slim-trixie (nom complet)" \
  _m12d_correspond "$_m12d_e05_df" '^FROM +docker\.io/library/python:3\.13-slim-trixie(@sha256:[0-9a-f]{64})?( |$)'
check_cmd "Dockerfile : aucune image « latest »" \
  bash -c '[[ -n "$1" ]] && ! grep -Eiq "(:latest|^FROM +[^: @]+( |$))" <<<"$1"' _ "$_m12d_e05_df"
check_cmd "Dockerfile : uv 0.12.23 épinglé, sans curl | sh ni pip install" \
  bash -c 'grep -Eq "uv:0\.12\.23" <<<"$1" && ! grep -Eq "(curl|wget)[^|]*\| *(ba)?sh|pip install" <<<"$1"' _ "$_m12d_e05_df"
check_cmd "Dockerfile : dépendances installées d'après le verrou, dans une étape sans le code" \
  bash -c 'grep -Eq -- "--locked|--frozen" <<<"$1" && grep -Eq -- "--no-install-(project|workspace)|uv export" <<<"$1"' _ "$_m12d_e05_df"
check_cmd "Dockerfile : USER non root" \
  bash -c 'grep -Eq "^USER +[^ ]+" <<<"$1" && ! grep -Eq "^USER +(root|0)(:|$| )" <<<"$1"' _ "$_m12d_e05_df"
check_cmd "Dockerfile : commande en forme exec" _m12d_correspond "$_m12d_e05_df" '^(CMD|ENTRYPOINT) +\['
_m12d_e05_di="$(_m12d_contenu_main mediagenda/api .dockerignore)"
# Liste noire (.git et .venv nommés) ou liste blanche (« * » puis des « ! ») : les deux excluent
# .git et .venv ; la liste blanche (M12-E10, E11) remplace souvent celle de E05 sur main.
check_cmd ".dockerignore : .git et .venv exclus du contexte" \
  bash -c '{ grep -Eq "^/?\.git/?$" <<<"$1" && grep -Eq "^/?\.venv/?$" <<<"$1"; } || { grep -Eq "^\*\s*$" <<<"$1" && ! grep -Eq "^!\s*/?\.(git|venv)" <<<"$1"; }' _ "$_m12d_e05_di"

# --- 2. L'image sur ctr01 --------------------------------------------------------------------------
_m12d_e05_img="$(_m12d_docker "image inspect --format '{{.Config.User}}|{{json .Config.Cmd}}|{{json .Config.Entrypoint}}|{{json .Config.ExposedPorts}}|{{json .Config.Env}}' mediagenda-api:0.1.0")"
check_cmd "ctr01 : image mediagenda-api:0.1.0 présente" test -n "$_m12d_e05_img"
check_cmd "Image : utilisateur 10001 (UID numérique, non root)" _m12d_correspond "$_m12d_e05_img" '^10001(:10001)?\|'
# _m12d_e05_exec INSPECT — ENTRYPOINT + CMD forment une commande qui lance mediagenda sans /bin/sh.
_m12d_e05_exec() {
  local cmd ep
  cmd="$(cut -d'|' -f2 <<<"$1")"
  ep="$(cut -d'|' -f3 <<<"$1")"
  jq -en --argjson c "${cmd:-null}" --argjson e "${ep:-null}" \
    '(($e // []) + ($c // [])) as $t | ($t | length > 0) and ($t[0] != "/bin/sh") and ($t | map(test("mediagenda")) | any)' >/dev/null 2>&1
}
check_cmd "Image : commande en forme exec (pas de /bin/sh -c en PID 1)" _m12d_e05_exec "$_m12d_e05_img"
check_cmd "Image : port 8000/tcp déclaré" _m12d_correspond "$_m12d_e05_img" '"8000/tcp"'
check_cmd "Image : MEDIAGENDA_VERSION=0.1.0" _m12d_correspond "$_m12d_e05_img" '"MEDIAGENDA_VERSION=0\.1\.0"'
check_cmd "Image : pas de secret dans l'environnement (ni DB_URL ni VALKEY_URL)" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "MEDIAGENDA_(DB|VALKEY)_URL=" <<<"$1"' _ "$_m12d_e05_img"

# --- 3. Le conteneur de test ------------------------------------------------------------------------
check_output "ctr01 : m12-e05-api tourne, issu de mediagenda-api:0.1.0" '^running mediagenda-api:0\.1\.0$' \
  _m12d_inspect m12-e05-api '{{.State.Status}} {{.Config.Image}}'
check_output "Depuis adm01 : /sante de m12-e05-api (port 8001) annonce la version 0.1.0" '"version": *"0\.1\.0"' \
  _m12d_http "http://$(_m12d_fqdn ctr01):8001/sante"
