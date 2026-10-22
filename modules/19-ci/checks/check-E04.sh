# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E04.sh — M19-E04 : un runner GitLab dans Kubernetes
# À lancer depuis adm01. Lecture seule : API Harbor et GitLab en GET (runners en lecture avec le jeton
# read_api + admin_mode des checks), objets Kubernetes (wb-checks : ConfigMap et Role, jamais les
# Secrets), ouverture TCP vers git01:443 depuis les travailleurs (SSH, rien n'est envoyé).

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E04 — Un runner GitLab dans Kubernetes"
require_cmd jq kubectl curl

# --- 1. Harbor : le cache des images de GitLab -----------------------------------------------------
check_cmd "Harbor : projet cache « gitlab » (registre amont associé)" _m19d_json \
  "$(harbor_api 'projects?name=gitlab' 2>/dev/null || true)" \
  'any(.[]; .name == "gitlab" and ((.registry_id // 0) > 0))'

# --- 2. Le runner dans GitLab ------------------------------------------------------------------------
_m19d_e04_id="$(_m19d_runner_id)"
if [[ -z "$_m19d_e04_id" ]]; then
  check_cmd "runner d'instance « $_M19D_RUNNER » présent dans GitLab" false
  skip "propriétés du runner $_M19D_RUNNER" "runner introuvable (GET /runners/all, type instance)"
else
  _m19d_e04_r="$(_m19d_api "runners/$_m19d_e04_id")"
  check_cmd "runner $_M19D_RUNNER (#$_m19d_e04_id) : d'instance, étiquettes k8s et kubernetes" _m19d_json "$_m19d_e04_r" '
    .runner_type == "instance_type" and ((.tag_list | index("k8s")) != null) and ((.tag_list | index("kubernetes")) != null)'
  check_cmd "runner $_M19D_RUNNER : ne prend pas les jobs sans étiquette, pas en pause" _m19d_json "$_m19d_e04_r" \
    '.run_untagged == false and .paused == false'
  check_cmd "runner $_M19D_RUNNER : en ligne" _m19d_json "$_m19d_e04_r" '.status == "online"'
  check_cmd "runner $_M19D_RUNNER : au moins un gestionnaire (runner manager) connu de GitLab" _m19d_json \
    "$(_m19d_api "runners/$_m19d_e04_id/managers")" 'length >= 1'
fi

# --- 3. Le gestionnaire dans le cluster -------------------------------------------------------------
check_cmd "Deployment gitlab-runner prêt, image du gestionnaire tirée par Harbor" _m19d_json \
  "$(_m19d_kj -n gitlab-runner get deployment gitlab-runner)" '
  (.status.readyReplicas // 0) >= 1
  and all(.spec.template.spec.containers[]; .image | startswith("registry.par1.medisphere.internal/"))'
_m19d_e04_cm="$(_m19d_kj -n gitlab-runner get configmap gitlab-runner)"
_m19d_e04_toml="$(jq -r '.data["config.template.toml"] // ""' <<<"${_m19d_e04_cm:-null}" 2>/dev/null || true)"
check_output "configuration : pods de job dans l'espace ci-jobs" '^\s*namespace\s*=\s*"ci-jobs"' printf '%s\n' "$_m19d_e04_toml"
check_output "configuration : compte de service des jobs ci-job" '^\s*service_account\s*=\s*"ci-job"' printf '%s\n' "$_m19d_e04_toml"
check_output "configuration : image helper tirée par Harbor" \
  '^\s*helper_image\s*=\s*"registry\.par1\.medisphere\.internal/' printf '%s\n' "$_m19d_e04_toml"
check_output "configuration : image par défaut des jobs tirée par Harbor" \
  '^\s*image\s*=\s*"registry\.par1\.medisphere\.internal/' printf '%s\n' "$_m19d_e04_toml"
check_cmd "aucun jeton glrt- dans le ConfigMap du gestionnaire" bash -c '[[ -n "$1" ]] && ! grep -q "glrt-" <<<"$1"' _ "$_m19d_e04_cm"
check_cmd "Role du gestionnaire DANS ci-jobs, sans « * » (création de pods, attach, exec)" _m19d_json \
  "$(_m19d_kj -n ci-jobs get roles)" '
  any(.items[]; any(.rules[]; ((.resources // []) | index("pods")) != null and ((.verbs // []) | index("create")) != null)
               and all(.rules[]; ((.resources // []) | index("*")) == null and ((.verbs // []) | index("*")) == null))'

# --- 4. Le premier pipeline ----------------------------------------------------------------------------
_m19d_e04_p="$(_m19d_pipelines "$_M19D_LABO" 'per_page=1')"
_m19d_e04_pid="$(jq -r '.[0].id // empty' <<<"${_m19d_e04_p:-[]}" 2>/dev/null || true)"
check_cmd "$_M19D_LABO : le dernier pipeline a réussi" _m19d_json "$_m19d_e04_p" '.[0].status == "success"'
if [[ -n "$_m19d_e04_pid" ]]; then
  check_cmd "$_M19D_LABO : un job du dernier pipeline a été exécuté par le runner $_M19D_RUNNER" _m19d_json \
    "$(_m19d_jobs "$_M19D_LABO" "$_m19d_e04_pid")" 'any(.[]; (.runner.description // "") == $r)' --arg r "$_M19D_RUNNER"
else
  skip "runner du dernier pipeline de $_M19D_LABO" "aucun pipeline"
fi

# --- 5. Réseau : les travailleurs joignent GitLab -------------------------------------------------------
for _m19d_e04_n in "${_M19D_W[@]}"; do
  check_ssh "$_m19d_e04_n : git01 joignable en TCP 443 (règle de la bordure)" "$_m19d_e04_n" \
    "timeout 3 bash -c '</dev/tcp/10.10.20.12/443'"
done

# --- 6. Le code sur main ----------------------------------------------------------------------------------
check_cmd "plateforme/k8s (main) : outils/secrets-k8s.sh" _m19d_fichier_main plateforme/k8s outils/secrets-k8s.sh
check_cmd "plateforme/k8s (main) : secrets/gitlab-runner.yml chiffré sous l'identité « critique »" \
  _m19d_vault_critique plateforme/k8s secrets/gitlab-runner.yml
check_cmd "plateforme/k8s (main) : release gitlab-runner dans le Helmfile (chart gitlab/gitlab-runner)" \
  _m19d_grep_main plateforme/k8s '^releases/.*\.gotmpl$' 'chart: *gitlab/gitlab-runner'
check_cmd "plateforme/k8s (main) : aucune trace de jeton glrt- dans les valeurs du runner" bash -c \
  '[[ -n "$1" ]] && ! grep -q "glrt-" <<<"$1"' _ "$(_m19d_contenu_main plateforme/k8s composants/gitlab-runner/values.yaml)"
check_cmd "plateforme/infra (main) : cache Harbor gitlab (registry.gitlab.com) dans l'état registre" \
  _m19d_grep_main plateforme/infra '^registre/.*\.tf$' 'registry\.gitlab\.com'
