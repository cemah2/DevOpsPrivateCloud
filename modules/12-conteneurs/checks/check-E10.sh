# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués par docker ou bash -c
#
# check-E10.sh — M12-E10 : Multi-étapes et image minimale pour MédiDoc
# À lancer depuis adm01. Lecture seule : API GitLab en GET, docker image inspect / save / exec de
# lecture sur ctr01 (SSH), requête HTTP vers le conteneur d'essai.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E10 — Multi-étapes et image minimale pour MédiDoc"
require_cmd jq curl

# --- 1. Le projet ------------------------------------------------------------------------------------
check_output "GitLab : projet medidoc/medidoc, branche par défaut main" '"default_branch": *"main"' \
  bash -c 'jq "{default_branch}" <<<"$1"' _ "$(_m12o_projet medidoc/medidoc)"
_m12o_e10_df="$(_m12o_fichier medidoc/medidoc Dockerfile)"
_m12o_e10_di="$(_m12o_fichier medidoc/medidoc .dockerignore)"
check_cmd "medidoc/medidoc (main) : go.mod et cmd/medidoc/main.go présents" \
  test -n "$(_m12o_fichier medidoc/medidoc go.mod)$(_m12o_fichier medidoc/medidoc cmd/medidoc/main.go)"
check_cmd "Dockerfile : au moins deux étapes (deux FROM)" \
  bash -c '[ "$(grep -Eic "^FROM " <<<"$1")" -ge 2 ]' _ "$_m12o_e10_df"
check_cmd "Dockerfile : la dernière étape part de distroless ou de scratch" \
  bash -c 'grep -Ei "^FROM " <<<"$1" | tail -n 1 | grep -Eq "distroless|^FROM +scratch"' _ "$_m12o_e10_df"
check_cmd "Dockerfile : binaire statique (CGO_ENABLED=0)" _m12o_correspond "$_m12o_e10_df" 'CGO_ENABLED=0'
check_cmd "Dockerfile : USER numérique non root, commande en forme exec" \
  bash -c 'grep -Eq "^USER +[1-9][0-9]*(:[0-9]+)?\s*$" <<<"$1" && grep -Eq "^(ENTRYPOINT|CMD) +\[" <<<"$1"' _ "$_m12o_e10_df"
check_cmd ".dockerignore : liste blanche (commence par « * ») qui écarte les tests Go" \
  bash -c 'grep -Eq "^\*\s*$" <<<"$1" && grep -Eq "_test\.go" <<<"$1"' _ "$_m12o_e10_di"

# --- 2. L'image sur ctr01 -------------------------------------------------------------------------------
_m12o_e10_img="$(_m12o_docker "image inspect --format '{{.Config.User}}|{{json .Config.Entrypoint}}|{{json .Config.Cmd}}|{{json .Config.Labels}}' medidoc:1.0.0")"
check_cmd "ctr01 : image medidoc:1.0.0 présente" test -n "$_m12o_e10_img"
check_cmd "Image : utilisateur numérique non root" _m12o_correspond "$_m12o_e10_img" '^[1-9][0-9]*(:[0-9]+)?\|'
check_cmd "Image : commande en forme exec, sans shell" \
  bash -c 'c="$(cut -d"|" -f2,3 <<<"$1")"; grep -q "medidoc" <<<"$c" && ! grep -Eq "\"/bin/(ba)?sh\"" <<<"$c"' _ "$_m12o_e10_img"
check_cmd "Image : étiquettes OCI title, version (1.0.0), source, vendor" \
  bash -c 'grep -q "org.opencontainers.image.title" <<<"$1" && grep -q "\"org.opencontainers.image.version\":\"1.0.0\"" <<<"$1" && grep -q "org.opencontainers.image.source" <<<"$1" && grep -q "org.opencontainers.image.vendor" <<<"$1"' _ "$_m12o_e10_img"
# Taille transférée : archive de docker save (blobs compressés avec le stockage containerd de Docker 29).
_m12o_e10_taille="$(_m12o_ssh "$_M12O_CTR01" 'docker save medidoc:1.0.0 2>/dev/null | wc -c')"
check_cmd "Image : moins de 30 Mo dans l'archive de docker save (${_m12o_e10_taille:-?} octets)" \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ] && [ "$1" -lt 31457280 ]' _ "$_m12o_e10_taille"

# --- 3. Le conteneur d'essai ------------------------------------------------------------------------------
check_output "ctr01 : m12-e10-doc tourne, issu de medidoc:1.0.0, port 8010 publié" '^running medidoc:1\.0\.0 .*8010' \
  _m12o_docker "inspect --format '{{.State.Status}} {{.Config.Image}} {{json .NetworkSettings.Ports}}' m12-e10-doc"
_m12o_e10_shell() {
  [[ "$(_m12o_docker "inspect --format '{{.State.Status}}' m12-e10-doc")" == running ]] || return 1
  ! remote "$_M12O_CTR01" "docker exec m12-e10-doc sh -c true" >/dev/null 2>&1
}
check_cmd "m12-e10-doc : aucun shell dans l'image (docker exec … sh échoue)" _m12o_e10_shell
check_output "Depuis adm01 : /healthz de m12-e10-doc (port 8010) annonce la version 1.0.0" '"version": *"1\.0\.0"' \
  curl -s --max-time "${WB_TIMEOUT:-5}" "http://$_M12O_NOM01:8010/healthz"
