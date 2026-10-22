# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E33.sh — M19-E33 « Accueillir l'équipe MédiDoc dans la CI »
# À lancer depuis adm01. Lecture seule : pipelines, jobs, configuration fusionnée et fichiers des
# projets medidoc/* (API de GitLab), artefact dans Harbor, Deployment de medidoc-dev (wb-checks).

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E33 — MédiDoc dans la CI"
require_cmd jq curl kubectl

title "Pipeline de medidoc/medidoc"
_m19_e33_l="$(_m19p_lint medidoc/medidoc)"
check_cmd "configuration valide, n'incluant que des composants (et des fichiers locaux)" _m19p_seulement_composants "$_m19_e33_l"
for _m19_e33_c in qualite construction-image securite promotion; do
  check_cmd "composant $_m19_e33_c inclus en 2.2.0 ou plus" _m19p_inclut_composant "$_m19_e33_l" "$_m19_e33_c" 2.2.0
done
check_cmd "tests avec le détecteur de concurrence (-race)" bash -c 'jq -r ".merged_yaml // empty" <<<"$1" | grep -q -- "-race"' _ "$_m19_e33_l"
for _m19_e33_t in main etiquette; do
  if [[ "$_m19_e33_t" == main ]]; then _m19_e33_pl="$(_m19p_pipeline_main medidoc/medidoc)"; else _m19_e33_pl="$(_m19p_pipeline_etiquette medidoc/medidoc)"; fi
  check_cmd "dernier pipeline ($_m19_e33_t) réussi" _m19p_jq "$_m19_e33_pl" '.status == "success"'
  if [[ "$_m19_e33_pl" != null ]]; then
    _m19_e33_j="$(_m19p_jobs medidoc/medidoc "$(jq -r .id <<<"$_m19_e33_pl")")"
    check_cmd "pipeline ($_m19_e33_t) : aucun job sur runner02 (étiquette docker)" _m19p_jq "$_m19_e33_j" \
      'length > 0 and all(.[]; (.tag_list | index("docker") | not) and ((.runner.description // "") | test("runner02") | not))'
    [[ "$_m19_e33_t" == main ]] && check_cmd "pipeline (main) : couverture relevée" _m19p_jq "$_m19_e33_pl" '.coverage != null'
    [[ "$_m19_e33_t" == etiquette ]] && check_cmd "pipeline (étiquette) : signature sur $_M19P_RUNNER_PROTEGE" \
      _m19p_job_sur "$_m19_e33_j" securite:signature "$_M19P_RUNNER_PROTEGE"
  fi
done
check_cmd "Harbor : dernière version de medisphere/medidoc signée et attestée" \
  _m19p_signee_attestee "$(_m19p_artefact_version medisphere medidoc)"

title "medidoc/deploiement"
check_cmd "base/kustomization.yaml sur main" _m19p_fichier_contient medidoc/deploiement base/kustomization.yaml 'resources'
check_cmd "overlays/dev : espace medidoc-dev, image par digest" \
  _m19p_fichier_contient medidoc/deploiement overlays/dev/kustomization.yaml 'medidoc-dev' 'digest: *sha256:[0-9a-f]{64}'
check_cmd "une MR de promotion promotion/dev-vX.Y.Z existe" _m19p_jq \
  "$(_m19p_gl "projects/$(_m19p_p medidoc/deploiement)/merge_requests?state=all&per_page=100")" \
  'any(.[]; .source_branch | test("^promotion/dev-v[0-9]+\\.[0-9]+\\.[0-9]+$"))'
check_cmd "medidoc/deploiement : fusion seulement si le pipeline a réussi" \
  _m19p_jq "$(_m19p_gl "projects/$(_m19p_p medidoc/deploiement)")" '.only_allow_merge_if_pipeline_succeeds == true'
check_cmd "medidoc/medidoc : DEPLOIEMENT_TOKEN protégée, masquée, de portée promotion/*" \
  _m19p_jq "$(_m19p_variables projects medidoc/medidoc)" \
  'any(.[]; .key == "DEPLOIEMENT_TOKEN" and .protected and .masked and .environment_scope == "promotion/*")'

title "Déploiement en dev"
_m19_e33_d="$(_m19p_json -n medidoc-dev get deployment medidoc)"
check_cmd "medidoc-dev/medidoc : image par digest de medisphere/medidoc" _m19p_jq "$_m19_e33_d" \
  'any(.spec.template.spec.containers[]; .image | test("/medisphere/medidoc@sha256:[0-9a-f]{64}$"))'
check_cmd "medidoc-dev/medidoc : réplicas disponibles" _m19p_jq "$_m19_e33_d" '(.status.availableReplicas // 0) >= 1'
