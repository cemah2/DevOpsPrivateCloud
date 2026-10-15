# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M14-E18 : Admission : Pod Security et ValidatingAdmissionPolicy
# À lancer depuis adm01. Lecture seule : espaces, politiques, pods (« kube »), GitLab.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E18 — Admission : Pod Security et ValidatingAdmissionPolicy"
require_cmd jq kubectl curl

_m14o_e18_ns="$(_m14o_k get namespaces -o json)"
_m14o_e18_psa() { # ESPACE MODE NIVEAU
  _m14o_json "$_m14o_e18_ns" 'any(.items[]; .metadata.name == $n and .metadata.labels["pod-security.kubernetes.io/" + $m] == $v)' \
    --arg n "$1" --arg m "$2" --arg v "$3"
}
_m14o_e18_warn_audit() { _m14o_e18_psa "$1" warn restricted && _m14o_e18_psa "$1" audit restricted; }
for _m14o_e18_x in mediagenda-dev mediagenda-recette; do
  check_cmd "$_m14o_e18_x : enforce=restricted" _m14o_e18_psa "$_m14o_e18_x" enforce restricted
  check_cmd "$_m14o_e18_x : version d'application figée (enforce-version v1.N)" _m14o_json "$_m14o_e18_ns" \
    'any(.items[]; .metadata.name == $n and ((.metadata.labels["pod-security.kubernetes.io/enforce-version"] // "") | test("^v1\\.[0-9]+$")))' --arg n "$_m14o_e18_x"
  check_cmd "$_m14o_e18_x : warn et audit en restricted" _m14o_e18_warn_audit "$_m14o_e18_x"
done
check_cmd "wb-essais : enforce=baseline" _m14o_e18_psa wb-essais enforce baseline
check_cmd "wb-system : enforce=restricted" _m14o_e18_psa wb-system enforce restricted

_m14o_e18_vap="$(_m14o_k get validatingadmissionpolicy medisphere-images -o json)"
_m14o_e18_vapb="$(_m14o_k get validatingadmissionpolicybinding medisphere-images -o json)"
check_cmd "ValidatingAdmissionPolicy medisphere-images, failurePolicy Fail, paramètre ConfigMap" _m14o_json "$_m14o_e18_vap" \
  '(.spec.failurePolicy // "Fail") == "Fail" and .spec.paramKind.kind == "ConfigMap"'
check_cmd "la politique vise les pods ET les contrôleurs (deployments, jobs, cronjobs…)" _m14o_json "$_m14o_e18_vap" \
  '[.spec.matchConstraints.resourceRules[].resources[]] as $r | ($r | index("pods")) != null and ($r | index("deployments")) != null
   and ($r | index("cronjobs")) != null and ($r | index("statefulsets")) != null'
check_cmd "la politique compile sans erreur de type (status.typeChecking)" _m14o_json "$_m14o_e18_vap" \
  '((.status.typeChecking.expressionWarnings // []) | length) == 0'
check_cmd "liaison en Deny, limitée aux espaces des équipes" _m14o_json "$_m14o_e18_vapb" \
  '(.spec.validationActions | index("Deny")) != null and .spec.policyName == "medisphere-images"
   and ([.spec.matchResources.namespaceSelector.matchExpressions[]?.key, (.spec.matchResources.namespaceSelector.matchLabels // {} | keys[])]
        | index("medisphere.internal/equipe")) != null'
check_cmd "ConfigMap de paramètres kube-system/medisphere-images : registre Harbor autorisé" \
  _m14o_json "$(_m14o_k get configmap medisphere-images -n kube-system -o json)" '.data.registres | contains("registry.par1.medisphere.internal/")'

_m14o_e18_pods="$(_m14o_k get pods -A -o json | jq '[.items[] | select(.metadata.namespace | startswith("mediagenda-")) | select(.status.phase == "Running" or .status.phase == "Pending")]' 2>/dev/null || true)"
check_cmd "des pods tournent dans les espaces MédiAgenda (sinon rien n'est vérifié)" _m14o_json "$_m14o_e18_pods" 'length >= 3'
check_cmd "tous ces pods respectent le profil restricted" _m14o_json "$_m14o_e18_pods" "all(.[]; $_M14O_RESTRICTED)"
check_cmd "toutes leurs images viennent de registry.par1.medisphere.internal, avec une version explicite" _m14o_json "$_m14o_e18_pods" \
  "[.[] | (.spec.containers + (.spec.initContainers // []))[].image] | all($_M14O_IMAGE_OK)"
check_cmd "plateforme/k8s : admission/ sur main" bash -c '[[ -n "$1" ]]' _ "$(_m14o_arbre "$_M14O_P_K8S" admission)"
check_output "plateforme/k8s : espaces/mediagenda-dev/00-namespace.yaml (main) porte les étiquettes Pod Security" \
  'pod-security\.kubernetes\.io/enforce: *"?restricted' _m14o_contenu_main "$_M14O_P_K8S" espaces/mediagenda-dev/00-namespace.yaml
check_output "journal ~/m14/e18/journal.md (étapes, limites)" '[Ee]ph[ée]m[èe]re|parameterNotFoundAction' cat "$_M14O_TRAVAIL/e18/journal.md"
