# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E14.sh — M20-E14 « Promouvoir une version de dev à la production, et revenir en arrière ».
# Lecture seule : mediagenda/deploiement et plateforme/medisphere (GitLab), Applications (wb-checks).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E14 — Promouvoir une version de dev à la production, et revenir en arrière"
require_cmd jq kubectl curl yq

_e14_p=mediagenda/deploiement
# _e14_digest ENV — digest de l'image de l'API dans overlays/ENV/kustomization.yaml (main).
_e14_digest() {
  _m20o_gl_fichier "$_e14_p" "overlays/$1/kustomization.yaml" \
    | IMG="$_M20O_IMAGE_API" yq -r '(.images // [])[] | select(.name == strenv(IMG)) | .digest // ""' 2>/dev/null || true
}
_e14_version() { _m20o_gl_fichier "$_e14_p" "overlays/$1/livraison.yaml" | yq -r '.data.version // ""' 2>/dev/null || true; }
for _e14_env in dev recette prod; do
  _e14_d="$(_e14_digest "$_e14_env")"
  check_cmd "overlays/$_e14_env : image de l'API désignée par un digest" \
    bash -c '[[ "$1" =~ ^sha256:[a-f0-9]{64}$ ]]' _ "$_e14_d"
  _e14_v="$(_e14_version "$_e14_env")"
  check_cmd "overlays/$_e14_env : version lisible vX.Y.Z dans livraison.yaml" \
    bash -c '[[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]' _ "$_e14_v"
  _e14_t="$(_m20o_gl_fichier "$_e14_p" "overlays/$_e14_env/kustomization.yaml" \
    | IMG="$_M20O_IMAGE_API" yq -r '(.images // [])[] | select(.name == strenv(IMG)) | .newTag // ""' 2>/dev/null || true)"
  check_cmd "overlays/$_e14_env : étiquette de l'image = version de livraison.yaml (promues ensemble)" \
    bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ "$_e14_t" "$_e14_v"
done

check_cmd "$_e14_p : outils/promouvoir.sh sur main" _m20o_gl_existe "$_e14_p" outils/promouvoir.sh
_e14_mr="$(_m20o_mr_fusionnees "$_e14_p")"
check_cmd "$_e14_p : au moins une promotion vers la recette fusionnée par MR (branche promotion/recette-…)" \
  _m20o_jq "$_e14_mr" '[.[] | select(.source_branch | startswith("promotion/recette-"))] | length >= 1'
check_cmd "$_e14_p : au moins une promotion vers la prod fusionnée par MR (branche promotion/prod-…)" \
  _m20o_jq "$_e14_mr" '[.[] | select(.source_branch | startswith("promotion/prod-"))] | length >= 1'
check_cmd "$_e14_p : les promotions sont fusionnées par quelqu'un d'autre que leur auteur" \
  _m20o_jq "$_e14_mr" '[.[] | select(.source_branch | startswith("promotion/")) | select(.merged_by.username == .author.username)] | length == 0'
_e14_revert() {
  gitlab_api "projects/$(_m20o_enc "$_e14_p")/repository/commits?ref_name=main&per_page=100" 2>/dev/null \
    | jq -e '[.[] | select(.title | test("^Revert \""))] | length >= 1' >/dev/null 2>&1
}
check_cmd "$_e14_p : un retour arrière par git revert sur main" _e14_revert

# Ce que dit Git est ce qui tourne : la prod synchronisée sur main (synchronisation manuelle faite).
# Juste après une fusion, Argo CD peut ne pas avoir encore relu le dépôt (jusqu'à 3 min) : relance.
_e14_prod="$(_m20o_app mediagenda-prod)"
check_cmd "mediagenda-prod : Synced et Healthy (synchronisation manuelle faite après la dernière MR)" \
  _m20o_sync_sante "$_e14_prod"
check_cmd "mediagenda-prod : toujours sans synchronisation automatique" \
  _m20o_jq "$_e14_prod" '(.spec.syncPolicy.automated // null) == null'
_e14_rec="$(_m20o_app mediagenda-recette)"
check_cmd "mediagenda-recette : synchronisation automatique toujours active (pas coupée pour un rollback)" \
  _m20o_jq "$_e14_rec" '.spec.syncPolicy.automated.selfHeal == true'
check_cmd "plateforme/medisphere : docs/livraison/gitops/promotion.md sur main" \
  _m20o_gl_existe plateforme/medisphere docs/livraison/gitops/promotion.md
_e14_doc() { _m20o_gl_fichier plateforme/medisphere docs/livraison/gitops/promotion.md | grep -Eiq 'revert'; }
check_cmd "promotion.md : le retour arrière par revert est décrit" _e14_doc
