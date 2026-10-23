# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E20.sh — M25-E20 « Signer avec une clé qui ne sort jamais du coffre ».
# Vérifie : clé cosign-medisphere (ECDSA P-256, non exportable…) ; la clé publique publiée dans
# docs/registre/cosign.pub EST celle du coffre (dernière version) et l'ancienne est gardée à part ;
# politique cosign-signature et rôle JWT ci-signature au plus juste (audience, référence protégée,
# runner protégé, 10 min) ; composant securite v2.10.0 et charts-miroir signent par « hashivault:// » ;
# le Secret de la clé et son montage ont disparu de plateforme/k8s ; la dernière version de
# mediagenda-api se vérifie avec la NOUVELLE clé publique.
# Lecture seule : OpenBao (métadonnées de la clé, rôle), GitLab, Harbor en lecture (cosign verify).

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E20 — Signer avec une clé qui ne sort jamais du coffre"
require_cmd jq curl cosign

_m25c_e20_cle="$(_m25c_cle cosign-medisphere)"
check_cmd "cosign-medisphere : ecdsa-p256, non exportable, sans sauvegarde en clair, non supprimable" \
  _m25c_json "$_m25c_e20_cle" '.type == "ecdsa-p256" and .exportable == false
    and .allow_plaintext_backup == false and .deletion_allowed == false'

# Clé publique de la dernière version, comparée (sans blancs) à celle publiée sur main.
_m25c_e20_pub_coffre="$(jq -r '.keys[(.latest_version | tostring)].public_key // empty' <<<"$_m25c_e20_cle" 2>/dev/null | tr -d ' \n\r' || true)"
_m25c_e20_pub_doc="$(_m25c_contenu "$_M25C_P_DOC" docs/registre/cosign.pub | tr -d ' \n\r')"
_m25c_e20_meme_cle() { [[ -n "$_m25c_e20_pub_coffre" && "$_m25c_e20_pub_coffre" == "$_m25c_e20_pub_doc" ]]; }
check_cmd "docs/registre/cosign.pub = clé publique de cosign-medisphere (dernière version du coffre)" _m25c_e20_meme_cle
_m25c_e20_pub_ancienne="$(_m25c_contenu "$_M25C_P_DOC" docs/registre/cosign-m13.pub | tr -d ' \n\r')"
_m25c_e20_ancienne() { [[ -n "$_m25c_e20_pub_ancienne" && "$_m25c_e20_pub_ancienne" != "$_m25c_e20_pub_doc" ]]; }
check_cmd "ancienne clé publique gardée à part (docs/registre/cosign-m13.pub), différente de la nouvelle" _m25c_e20_ancienne

_m25c_e20_pol="$(_m25c_politique cosign-signature)"
check_cmd "politique cosign-signature : signer (sha2-256) et lire la clé publique" \
  bash -c 'grep -q "path \"transit/sign/cosign-medisphere/sha2-256\"" <<<"$1" && grep -q "path \"transit/keys/cosign-medisphere\"" <<<"$1"' _ "$_m25c_e20_pol"
check_cmd "politique cosign-signature : aucun export, aucune sauvegarde, aucun réglage de la clé" \
  bash -c '[[ -n "$1" ]] && ! grep -Pzo "path \"transit/(export|backup|keys/cosign-medisphere/)[^\"]*\"\s*\{\s*capabilities\s*=\s*\[[^\]]*\"(read|update|create)\"" <<<"$1" >/dev/null' _ "$_m25c_e20_pol"

_m25c_e20_role="$(bao_api auth/gitlab/role/ci-signature 2>/dev/null | jq -c '.data // empty' 2>/dev/null || true)"
if [[ -z "$_m25c_e20_role" ]]; then
  check_cmd "rôle JWT auth/gitlab/role/ci-signature lisible" false
else
  check_cmd "ci-signature : audience openbao.medisphere.internal seule, politique cosign-signature seule" \
    _m25c_json "$_m25c_e20_role" '.bound_audiences == ["openbao.medisphere.internal"] and .token_policies == ["cosign-signature"]'
  check_cmd "ci-signature : références protégées seulement (ref_protected = \"true\")" \
    _m25c_json "$_m25c_e20_role" '[.bound_claims.ref_protected] | flatten | . == ["true"]'
  check_cmd "ci-signature : lié au runner protégé (runner_id NUMÉRIQUE, type de comparaison « string »)" \
    _m25c_json "$_m25c_e20_role" '.bound_claims_type == "string" and ([.bound_claims.runner_id] | flatten | length > 0 and all(type == "number"))'
  check_cmd "ci-signature : jetons de 15 min au plus" \
    _m25c_json "$_m25c_e20_role" '.token_ttl > 0 and .token_ttl <= 900 and .token_max_ttl > 0 and .token_max_ttl <= 900'
fi

check_cmd "plateforme/ci-templates : étiquette v2.10.0 publiée" _m25c_etiquette "$_M25C_P_CI" v2.10.0
check_cmd "composant securite (main) : signature par hashivault://, plus de clé montée" \
  bash -c 'grep -q "hashivault://cosign-medisphere" <<<"$1" && ! grep -Eq "cle_cosign|/run/secrets/medisphere/cosign" <<<"$1"' _ \
  "$(_m25c_contenu "$_M25C_P_CI" templates/securite/template.yml)"
check_cmd "plateforme/charts-miroir : signer.sh signe par la clé du coffre" \
  _m25c_contient plateforme/charts-miroir outils/signer.sh 'hashivault://cosign-medisphere'
check_cmd "plateforme/k8s : plus de montage de la clé dans le runner protégé" \
  _m25c_ne_contient_pas "$_M25C_P_K8S" composants/gitlab-runner-protege/values.yaml 'cosign-medisphere'
check_cmd "plateforme/k8s : plus de Secret cosign-ci dans secrets-k8s.conf" \
  _m25c_ne_contient_pas "$_M25C_P_K8S" outils/secrets-k8s.conf '^[[:space:]]*cosign-ci[[:space:]]'

# Dernière étiquette de mediagenda/api : l'image se vérifie avec la NOUVELLE clé publique (re-signée
# si elle est antérieure au changement de clé). Identité Harbor de LECTURE des checks, passée par un
# fichier de configuration temporaire (jamais en argument).
_m25c_e20_verifier() {
  local f="${WB_HARBOR_CHECKS_FILE:-$HOME/.config/workbook/harbor-checks.env}" HARBOR_USER="" HARBOR_PASSWORD="" tag d rc
  [[ -r "$f" ]] || return 1
  # shellcheck disable=SC1090
  source "$f"
  tag="$(gitlab_api "projects/$(_m25c_uri mediagenda/api)/repository/tags?per_page=1&order_by=updated" 2>/dev/null | jq -r '.[0].name // empty')"
  [[ -n "$tag" && -n "$_m25c_e20_pub_doc" ]] || return 1
  d="$(mktemp -d)"
  _m25c_contenu "$_M25C_P_DOC" docs/registre/cosign.pub >"$d/cosign.pub"
  printf '{"auths":{"registry.par1.medisphere.internal":{"auth":"%s"}}}' \
    "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" >"$d/config.json"
  DOCKER_CONFIG="$d" timeout 60 cosign verify --key "$d/cosign.pub" --insecure-ignore-tlog=true \
    "registry.par1.medisphere.internal/medisphere/mediagenda-api:$tag" >/dev/null 2>&1
  rc=$?
  rm -rf "$d"
  return "$rc"
}
check_cmd "dernière version de mediagenda-api : signature vérifiée avec la NOUVELLE clé publique" _m25c_e20_verifier
check_cmd "décision écrite ($_M25C_DOC_SECRETS/cle-signature.md : nouvelle clé, re-signature, rotation)" \
  _m25c_contient "$_M25C_P_DOC" "$_M25C_DOC_SECRETS/cle-signature.md" '[Rr]e-?signature'
