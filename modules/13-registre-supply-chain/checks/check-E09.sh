# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E09.sh — M13-E09 : La chaîne de livraison d'une image
# À lancer depuis adm01. Lecture seule : GitLab en GET (gabarit, inclusion, pipelines, variables),
# API de Harbor, cosign verify avec wb-checks.

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E09 — La chaîne de livraison d'une image"
require_cmd jq cosign

_m13_api_p="projects/mediagenda%2Fapi"
_m13_tpl="$(_m13d_contenu_main "$_M13D_CITPL" templates/supply-chain.yml)"

# --- Gabarit -----------------------------------------------------------------------------------------
check_cmd "plateforme/ci-templates (main) : templates/supply-chain.yml présent" test -n "$_m13_tpl"
_m13_images_harbor() {
  # Toute valeur d'image (clé image:, name:, variable IMAGE_* ou *_IMAGE) littérale désigne Harbor, avec empreinte.
  local l n=0
  while IFS= read -r l; do
    n=$((n + 1))
    [[ "$l" == "$_M13D_NOM/"*"@sha256:"* ]] || return 1
  done < <(grep -Eo '^[[:space:]]*(image|name|[A-Z_]*IMAGE[A-Z_]*)[[:space:]]*:[[:space:]]*["'"'"']?[^ "'"'"'$#[][^ "'"'"']*' <<<"$_m13_tpl" \
             | sed -E 's/^[^:]*:[[:space:]]*["'"'"']?//')
  (( n >= 1 ))
}
check_cmd "supply-chain.yml : images de Harbor uniquement, épinglées par empreinte" _m13_images_harbor
check_cmd "supply-chain.yml : aucun job autorisé à échouer" bash -c '[[ -n "$1" ]] && ! grep -Eq "allow_failure:[[:space:]]*true" <<<"$1"' _ "$_m13_tpl"
check_cmd "supply-chain.yml : ni latest, ni mode privilégié, ni docker:dind" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq ":latest|privileged|docker:dind" <<<"$1"' _ "$_m13_tpl"
check_cmd "supply-chain.yml : Trivy bloquant sur critique corrigeable, Syft, Cosign sign/attest/verify" \
  bash -c 'for m in "--exit-code 1" "--ignore-unfixed" "syft " "cosign sign" "cosign attest" "cosign verify"; do grep -qF -- "$m" <<<"$1" || exit 1; done' _ "$_m13_tpl"
check_cmd "supply-chain.yml : signature sans journal public (--signing-config, --insecure-ignore-tlog)" \
  bash -c 'grep -q -- "--signing-config" <<<"$1" && grep -q -- "--insecure-ignore-tlog" <<<"$1" && ! grep -q -- "--tlog-upload" <<<"$1"' _ "$_m13_tpl"
_m13_etiq_tpl() { gitlab_api "$_M13D_CITPL/repository/tags?per_page=1" 2>/dev/null | jq -e 'length >= 1' >/dev/null 2>&1; }
check_cmd "plateforme/ci-templates : au moins une étiquette (référence épinglable)" _m13_etiq_tpl

# --- Client mediagenda/api ------------------------------------------------------------------------------
_m13_ci="$(_m13d_contenu_main "$_m13_api_p" .gitlab-ci.yml)"
_m13_inclusion() {
  grep -q 'plateforme/ci-templates' <<<"$_m13_ci" && grep -q 'templates/supply-chain.yml' <<<"$_m13_ci" \
    && grep -Eq '^[[:space:]]*ref:[[:space:]]*["'"'"']?v[0-9]+\.[0-9]+' <<<"$_m13_ci"
}
check_cmd "mediagenda/api (main) : inclut supply-chain.yml par une étiquette épinglée" _m13_inclusion

_m13_tag="$(gitlab_api "$_m13_api_p/repository/tags?order_by=version&per_page=20" 2>/dev/null \
  | jq -r '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty' 2>/dev/null || true)"
if [[ -z "$_m13_tag" ]]; then
  _ko "mediagenda/api : aucune étiquette Git vX.Y.Z"
else
  _m13_pipe() {
    gitlab_api "$_m13_api_p/pipelines?ref=$_m13_tag&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
  }
  check_cmd "mediagenda/api : le dernier pipeline de $_m13_tag a réussi" _m13_pipe
  _m13_d="$(_m13d_empreinte medisphere mediagenda-api "$_m13_tag")"
  check_cmd "Harbor : medisphere/mediagenda-api:$_m13_tag existe" test -n "$_m13_d"
  _m13_ref="$_M13D_NOM/medisphere/mediagenda-api@${_m13_d:-sha256:absent}"
  check_cmd "mediagenda-api:$_m13_tag : signature vérifiée avec la clé publiée" _m13d_cosign_verifie "$_m13_ref"
  check_cmd "mediagenda-api:$_m13_tag : attestation SPDX vérifiée" _m13d_attestation_verifiee "$_m13_ref" spdxjson
fi

# --- Variables du groupe mediagenda ----------------------------------------------------------------------
_m13_u="$(_m13o_var_groupe mediagenda HARBOR_ROBOT_USER)"
_m13_t="$(_m13o_var_groupe mediagenda HARBOR_ROBOT_TOKEN)"
check_cmd "groupe mediagenda : HARBOR_ROBOT_USER = robot\$medisphere+ci, protégée, non développée" \
  jq -e '.value == "robot$medisphere+ci" and .protected == true and .raw == true' <<<"${_m13_u:-null}"
check_cmd "groupe mediagenda : HARBOR_ROBOT_TOKEN protégée, masquée, non développée" \
  jq -e '.protected == true and .masked == true and .raw == true' <<<"${_m13_t:-null}"
check_cmd "docs/registre/chaine-livraison.md sur main" _m13o_doc docs/registre/chaine-livraison.md
