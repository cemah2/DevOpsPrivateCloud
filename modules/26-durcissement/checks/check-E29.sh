# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E29.sh — M26-E29 « Tetragon en application : bloquer »
# À lancer depuis adm01. Lecture seule : TracingPolicy et TracingPolicyNamespaced (compte wb-checks,
# ClusterRole wb-checks-securite étendue en E20), événements de Tetragon (Loki, locataire audit),
# règles du ruler, état de la recette de MédiAgenda, runbook RB-260 sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E29 — Tetragon en application : bloquer"
require_cmd kubectl jq curl

title "Politiques d'application"
_m26_e29_tpn() { _m26p_json -n "$1" get tracingpoliciesnamespaced.cilium.io "$2"; }
_m26_e29_actions='[.spec.kprobes[]?.selectors[]?.matchActions[]?.action] | map(ascii_downcase)'
_m26_e29_a="$(_m26_e29_tpn wb-essais bloquer-exec-tmp)"
check_cmd "wb-essais/bloquer-exec-tmp : crochet d'exécution, /tmp visé, action d'application" _m26p_jq "$_m26_e29_a" \
  "any(.spec.kprobes[]; .call | test(\"bprm\")) and ([.spec.kprobes[].selectors[].matchArgs[]?.values[]?] | any(startswith(\"/tmp\")))
   and ($_m26_e29_actions | any(. == \"override\" or . == \"sigkill\"))"
_m26_e29_b="$(_m26_e29_tpn wb-essais proteger-fichiers-systeme)"
check_cmd "wb-essais/proteger-fichiers-systeme : security_file_permission, action d'application" _m26p_jq "$_m26_e29_b" \
  "any(.spec.kprobes[]; .call == \"security_file_permission\") and ($_m26_e29_actions | any(. == \"override\" or . == \"sigkill\"))"
_m26_e29_c="$(_m26_e29_tpn mediagenda-recette proteger-fichiers-systeme)"
check_cmd "mediagenda-recette/proteger-fichiers-systeme : limitée aux pods de l'API (podSelector)" _m26p_jq "$_m26_e29_c" \
  '(.spec.podSelector.matchLabels["app.kubernetes.io/component"] // "") == "api"
   and any(.spec.kprobes[]; .call == "security_file_permission")'
check_cmd "aucune lecture de fichier sous tout /etc n'est bloquée (règle trop large)" _m26p_jq "$_m26_e29_c" \
  '[.spec.kprobes[].selectors[] | select(any(.matchArgs[]?; .index == 1 and any(.values[]; . == "4")))
    | .matchArgs[] | select(.index == 0) | .values[] | select(. == "/etc" or . == "/etc/")] | length == 0'
_m26_e29_tp="$(_m26p_json get tracingpolicies.cilium.io)"
check_cmd "aucune TracingPolicy de cluster ne porte d'action Sigkill ou Override" _m26p_jq "$_m26_e29_tp" \
  '[.items[] | .spec.kprobes[]?.selectors[]?.matchActions[]?.action | ascii_downcase | select(. == "sigkill" or . == "override")] | length == 0'

title "Essais et recette"
check_cmd "des opérations ont été bloquées dans wb-essais (événements Tetragon, 30 derniers jours)" _m26p_loki_trouve \
  '{service="tetragon"} |~ `KPROBE_ACTION_(SIGKILL|OVERRIDE)` |= `"wb-essais"`' audit 720h
# L'API de recette est un Rollout (Argo Rollouts, M20, workloadRef) ; à défaut, le Deployment.
_m26_e29_recette_prete() {
  local r
  r="$(_m26p_json -n mediagenda-recette get rollouts.argoproj.io mediagenda)"
  if [[ "$r" != null ]]; then
    _m26p_jq "$r" '.status.phase == "Healthy" and (.status.readyReplicas // 0) >= 1'
  else
    _m26p_pret mediagenda-recette deployment mediagenda
  fi
}
check_cmd "API de recette prête (Rollout ou Deployment mediagenda)" _m26_e29_recette_prete
_m26_e29_pods="$(_m26p_json -n mediagenda-recette get pods -l app.kubernetes.io/component=api)"
check_cmd "aucun conteneur de l'API de recette n'a été tué par SIGKILL (code 137) depuis son démarrage" _m26p_jq "$_m26_e29_pods" \
  '(.items | length) > 0 and ([.items[].status.containerStatuses[]? | select((.lastState.terminated.exitCode // 0) == 137)] | length == 0)'

title "Alerte et arrêt d'urgence"
check_output "règle TetragonProcessusTue chargée (ruler de Loki, locataire audit)" 'alert: *TetragonProcessusTue$' \
  _m26p_regles_loki audit
check_cmd "$_M26P_DOC : RB-260 contient l'arrêt d'urgence des politiques d'application" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement/runbooks 'RB-260' 15 'urgence' 'tracingpolicynamespaced|tetragon'
