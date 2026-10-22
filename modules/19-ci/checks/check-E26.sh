# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes
#
# check-E26.sh — M19-E26 « Monter GitLab, les runners et l'agent en 19.5 »
# À lancer depuis adm01. Lecture seule : API de GitLab (version, gestionnaires des runners, pipelines),
# git01, runner01 et runner02 en SSH (consultation : dpkg, gitlab-psql en lecture, gitlab-runner
# --version), Deployments des runners et de l'agent (compte wb-checks).

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E26 — GitLab, runners et agent en 19.5"
require_cmd jq curl ssh kubectl

title "GitLab"
check_cmd "GitLab répond en 19.5.x (API /version)" _m19p_jq "$(_m19p_gl version)" '.version | startswith("19.5.")'
check_ssh_output "git01 : paquet gitlab-ce en 19.5.x" git01 '^19\.5\.[0-9]+-ce\.' 'dpkg-query -W -f="\${Version}" gitlab-ce'
check_ssh "git01 : gitlab-ce figé (apt-mark hold)" git01 'apt-mark showhold | grep -qx gitlab-ce'
check_ssh_output "git01 : aucune migration d'arrière-plan en attente ni en échec" git01 '^0$' \
  'sudo -n gitlab-psql -At -c "SELECT count(*) FROM batched_background_migrations WHERE status NOT IN (1, 3, 6);" 2>/dev/null | tail -n 1'

title "Runners"
for _m19_e26_d in "$_M19P_RUNNER" "$_M19P_RUNNER_PROTEGE"; do
  _m19_e26_r="$(_m19p_runner "$_m19_e26_d")"
  _m19_e26_id="$(jq -r '.id // empty' <<<"$_m19_e26_r" 2>/dev/null || true)"
  if [[ -z "$_m19_e26_id" ]]; then
    check_cmd "runner $_m19_e26_d trouvé dans GitLab" false
    continue
  fi
  _m19_e26_g="$(_m19p_gestionnaires "$_m19_e26_id")"
  check_cmd "$_m19_e26_d : au moins un gestionnaire en ligne" _m19p_jq "$_m19_e26_g" 'any(.[]; .status == "online")'
  check_cmd "$_m19_e26_d : tous les gestionnaires en ligne sont en 19.5.x" _m19p_jq "$_m19_e26_g" \
    '[.[] | select(.status == "online")] | length > 0 and all(.[]; .version | startswith("19.5."))'
done
for _m19_e26_rel in gitlab-runner gitlab-runner-protege; do
  check_output "release $_m19_e26_rel : chart gitlab-runner 0.94.x" '^gitlab-runner-0\.94\.' \
    kube -n "$_M19P_RUNNER_NS" get deployment "$_m19_e26_rel" -o 'jsonpath={.metadata.labels.chart}'
done
check_ssh_output "runner01 : GitLab Runner 19.5.x" runner01 '^Version: +19\.5\.' 'gitlab-runner --version'
check_ssh_output "runner02 : GitLab Runner 19.5.x" runner02 '^Version: +19\.5\.' 'gitlab-runner --version'

title "Agent"
_m19_e26_ag="$(_m19p_json -n gitlab-agent get deployments)"
check_cmd "agent : image agentk en v19.5.x" _m19p_jq "$_m19_e26_ag" \
  'any(.items[]; any(.spec.template.spec.containers[]; .image | test(":v19\\.5\\.")))'
check_cmd "agent : adresse de KAS en grpcs://" _m19p_jq "$_m19_e26_ag" \
  'any(.items[]; any(.spec.template.spec.containers[].args[]?; startswith("--kas-address=grpcs://")))'
check_cmd "agent : tous les réplicas prêts" _m19p_jq "$_m19_e26_ag" \
  '(.items | length) > 0 and all(.items[]; (.status.readyReplicas // 0) >= (.spec.replicas // 1))'

title "Pipelines après la montée"
_m19_e26_v="$(_m19p_gl version | jq -r '.version // empty' 2>/dev/null || true)"
check_cmd "mediagenda/api : dernier pipeline d'étiquette réussi" _m19p_jq "$(_m19p_pipeline_etiquette mediagenda/api)" '.status == "success"'
check_cmd "mediagenda/deploiement : dernier pipeline de main réussi" _m19p_jq "$(_m19p_pipeline_main mediagenda/deploiement)" '.status == "success"'

title "Documentation"
check_cmd "plan de changement CHG-2026 sur main (retour arrière, compte rendu)" \
  _m19p_doc_prefixe plateforme/medisphere docs/livraison/ci CHG-2026 'retour arri' 'compte rendu'
check_cmd "RB-192 sur main (docs/livraison/ci/runbooks/ : gestionnaires, agent)" _m19p_doc_prefixe plateforme/medisphere docs/livraison/ci/runbooks RB-192 'managers|gestionnaire' 'agent'
[[ -n "$_m19_e26_v" ]] && echo "  (version de GitLab lue : $_m19_e26_v)"
