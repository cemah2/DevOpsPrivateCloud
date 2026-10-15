# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués par podman ou bash -c
#
# check-E13.sh — M12-E13 : Buildah et Skopeo : construire sans démon, copier entre registres
# À lancer depuis adm01. Lecture seule : podman image inspect et stat sous le compte app de ctr02,
# API du registre de travail en GET (compte plateforme), API GitLab en GET.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E13 — Buildah et Skopeo : construire sans démon, copier entre registres"
require_cmd jq curl

# --- 1. Les images du compte app --------------------------------------------------------------------------
_m12o_e13_mg="$(_m12o_app "$_M12O_CTR02" "podman image inspect --format '{{.Config.User}}|{{.Labels}}' localhost/mediagenda-api:0.2.0")"
check_cmd "ctr02 (app) : localhost/mediagenda-api:0.2.0 présente, utilisateur 10001" _m12o_correspond "$_m12o_e13_mg" '^10001(:10001)?\|'
_m12o_e13_diag="$(_m12o_app "$_M12O_CTR02" "podman image inspect --format '{{.Config.User}}|{{json .Config.Labels}}' localhost/m12/diag:1.0")"
check_cmd "ctr02 (app) : localhost/m12/diag:1.0 présente" test -n "$_m12o_e13_diag"
check_cmd "localhost/m12/diag:1.0 : utilisateur numérique non root" _m12o_correspond "$_m12o_e13_diag" '^[1-9][0-9]*(:[0-9]+)?\|'
check_cmd "localhost/m12/diag:1.0 : étiquettes OCI (title, version)" \
  bash -c 'grep -q "org.opencontainers.image.title" <<<"$1" && grep -q "org.opencontainers.image.version" <<<"$1"' _ "$_m12o_e13_diag"
check_ssh "ctr02 : ~app/.config/containers/auth.json en 600, propriété de app" "$_M12O_CTR02" \
  'sudo -n stat -c "%a %U" /home/app/.config/containers/auth.json | grep -qx "600 app"'

# --- 2. Le miroir dans le registre ---------------------------------------------------------------------------
check_cmd "adm01 : identifiants du registre lisibles ($_M12O_REGISTRE_ENV)" _m12o_registre_lisible
for _m12o_e13_r in "miroir/debian:trixie-slim" "miroir/python:3.13-slim-trixie"; do
  check_cmd "registre : $_m12o_e13_r en linux/amd64 et linux/arm64" \
    _m12o_multi_plateformes "${_m12o_e13_r%%:*}" "${_m12o_e13_r#*:}"
done

# --- 3. Le code ----------------------------------------------------------------------------------------------
_m12o_e13_arbre="$(gitlab_api "projects/plateforme%2Foutils/repository/tree?ref=main&recursive=true&per_page=100&path=conteneurs" 2>/dev/null | jq -r '.[].path' 2>/dev/null || true)"
check_cmd "plateforme/outils (main) : conteneurs/construire-diag.sh" _m12o_correspond "$_m12o_e13_arbre" 'construire-diag\.sh$'
check_cmd "plateforme/outils (main) : conteneurs/miroir.yaml" _m12o_correspond "$_m12o_e13_arbre" 'miroir\.ya?ml$'
