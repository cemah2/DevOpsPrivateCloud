# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M19-E29 « Chaîne d'approvisionnement : SBOM, provenance, signature, vérification »
# À lancer depuis adm01. Lecture seule : artefact et accessoires dans Harbor (robot des checks), jobs
# et réglages de projets par l'API de GitLab, composant deploiement sur main de plateforme/ci-templates.

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E29 — Chaîne d'approvisionnement"
require_cmd jq curl

title "Côté producteur (mediagenda/api)"
_m19_e29_a="$(_m19p_artefact_version medisphere mediagenda-api)"
check_cmd "Harbor : une version vX.Y.Z de medisphere/mediagenda-api existe" test "$_m19_e29_a" != null
check_cmd "Harbor : cette version porte une signature Cosign et au moins deux autres référents (SBOM, provenance)" \
  _m19p_signee_attestee "$_m19_e29_a"
_m19_e29_pl="$(_m19p_pipeline_etiquette mediagenda/api)"
if [[ "$_m19_e29_pl" == null ]]; then
  check_cmd "mediagenda/api : un pipeline d'étiquette existe" false
else
  _m19_e29_jobs="$(_m19p_jobs mediagenda/api "$(jq -r .id <<<"$_m19_e29_pl")")"
  check_cmd "dernière étiquette : signature et attestations sur $_M19P_RUNNER_PROTEGE" \
    _m19p_job_sur "$_m19_e29_jobs" securite:signature "$_M19P_RUNNER_PROTEGE"
  check_cmd "dernière étiquette : vérification du producteur réussie" \
    _m19p_jq "$_m19_e29_jobs" 'any(.[]; .name == "securite:verification" and .status == "success")'
fi
check_cmd "mediagenda/api inclut le composant securite en 2.2.0 ou plus" \
  _m19p_inclut_composant "$(_m19p_lint mediagenda/api)" securite 2.2.0

title "Côté consommateur (mediagenda/deploiement)"
check_cmd "plateforme/ci-templates : le composant deploiement contient la porte verifier-images" \
  _m19p_fichier_contient plateforme/ci-templates templates/deploiement/template.yml 'verifier-images' 'verify-attestation' 'slsaprovenance1'
check_cmd "mediagenda/deploiement inclut le composant deploiement en 2.2.0 ou plus" \
  _m19p_inclut_composant "$(_m19p_lint mediagenda/deploiement)" deploiement 2.2.0
check_cmd "mediagenda/deploiement : fusion seulement si le pipeline a réussi" \
  _m19p_jq "$(_m19p_gl "projects/$(_m19p_p mediagenda/deploiement)")" '.only_allow_merge_if_pipeline_succeeds == true'
_m19_e29_mr="$(_m19p_pipeline_mr mediagenda/deploiement)"
if [[ "$_m19_e29_mr" == null ]]; then
  check_cmd "mediagenda/deploiement : un pipeline de MR existe" false
else
  check_cmd "dernier pipeline de MR : verifier-images a tourné, bloquant (allow_failure: false)" \
    _m19p_jq "$(_m19p_jobs mediagenda/deploiement "$(jq -r .id <<<"$_m19_e29_mr")")" \
    'any(.[]; .name == "verifier-images" and .allow_failure == false and (.status == "success" or .status == "failed"))'
fi
check_cmd "essai inverse : au moins un job verifier-images en échec (image refusée)" _m19p_jq \
  "$(_m19p_gl "projects/$(_m19p_p mediagenda/deploiement)/jobs?scope%5B%5D=failed&per_page=100")" 'any(.[]; .name == "verifier-images")'

title "Documentation"
check_cmd "chaine-approvisionnement.md sur main (ce que la porte vérifie et ne vérifie pas, urgence)" \
  _m19p_fichier_contient plateforme/medisphere docs/livraison/ci/chaine-approvisionnement.md 'slsaprovenance1|provenance' 'urgence' 'digest'
