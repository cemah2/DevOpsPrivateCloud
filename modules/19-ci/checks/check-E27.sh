# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E27.sh — M19-E27 « Capacité et disponibilité des runners »
# À lancer depuis adm01. Lecture seule : Deployment, pods, PDB et ConfigMap du runner, PriorityClass
# (compte wb-checks) ; gestionnaires du runner et jobs de formation/ci-labo (API de GitLab).

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E27 — Capacité et disponibilité des runners"
require_cmd kubectl jq curl

title "Disponibilité du gestionnaire"
_m19_e27_d="$(_m19p_json -n "$_M19P_RUNNER_NS" get deployment gitlab-runner)"
check_cmd "gitlab-runner : 2 réplicas demandés et prêts" _m19p_jq "$_m19_e27_d" '.spec.replicas >= 2 and (.status.readyReplicas // 0) >= 2'
check_cmd "gitlab-runner : réplicas sur des nœuds différents" _m19p_jq "$(_m19p_json -n "$_M19P_RUNNER_NS" get pods -l app=gitlab-runner)" \
  '[.items[] | select(.status.phase == "Running") | .spec.nodeName] | unique | length >= 2'
check_cmd "PDB du gestionnaire : couvre ses pods et autorise une interruption" \
  _m19p_jq "$(_m19p_json -n "$_M19P_RUNNER_NS" get poddisruptionbudgets)" \
  'any(.items[]; .spec.selector.matchLabels.app == "gitlab-runner" and (.status.disruptionsAllowed // 0) >= 1)'
_m19_e27_id="$(_m19p_runner "$_M19P_RUNNER" | jq -r '.id // empty' 2>/dev/null || true)"
check_cmd "runner $_M19P_RUNNER : au moins 2 gestionnaires en ligne" \
  _m19p_jq "$(if [[ -n "$_m19_e27_id" ]]; then _m19p_gestionnaires "$_m19_e27_id"; else echo null; fi)" \
  '[.[] | select(.status == "online")] | length >= 2'

title "Priorité et réglages de débit"
check_cmd "PriorityClass medisphere-ci : sous medisphere-standard, sans préemption" \
  _m19p_jq "$(_m19p_json get priorityclass medisphere-ci)" '.value < 10000 and .preemptionPolicy == "Never" and (.globalDefault | not)'
_m19_e27_toml="$(_m19p_toml gitlab-runner)"
check_cmd "configuration : pods de job en medisphere-ci" _m19p_toml_a "$_m19_e27_toml" '^\s*priority_class_name\s*=\s*"medisphere-ci"'
check_cmd "configuration : concurrent explicite" _m19p_toml_a "$_m19_e27_toml" '^\s*concurrent\s*=\s*[1-9][0-9]*'
check_cmd "configuration : limit explicite (> 0)" _m19p_toml_a "$_m19_e27_toml" '^\s*limit\s*=\s*[1-9][0-9]*'
check_cmd "configuration : request_concurrency > 1" _m19p_toml_a "$_m19_e27_toml" '^\s*request_concurrency\s*=\s*([2-9]|[1-9][0-9]+)\s*$'
check_cmd "configuration : maximums de surcharge mémoire et CPU posés" bash -c \
  'grep -Eq "^\s*memory_limit_overwrite_max_allowed\s*=" <<<"$1" && grep -Eq "^\s*cpu_limit_overwrite_max_allowed\s*=" <<<"$1"' _ "$_m19_e27_toml"

title "Essai de charge"
_m19_e27_j="$(_m19p_gl "projects/$(_m19p_p formation/ci-labo)/jobs?scope%5B%5D=success&per_page=100")"
check_cmd "formation/ci-labo : un pipeline avec au moins 20 jobs « charge » réussis" _m19p_jq "$_m19_e27_j" \
  '[.[] | select(.name | test("^charge [0-9]+/[0-9]+$"))] | group_by(.pipeline.id) | (map(length) | max // 0) >= 20'

title "Documentation"
check_cmd "capacite-runners.md sur main (calcul, mesures, seuil)" \
  _m19p_fichier_contient plateforme/medisphere docs/livraison/ci/capacite-runners.md 'request_concurrency' 'seuil' 'p95|centile|médiane'
check_cmd "RB-193 sur main (docs/livraison/ci/runbooks/)" _m19p_doc_prefixe plateforme/medisphere docs/livraison/ci/runbooks RB-193 'quota' 'concurrent'
