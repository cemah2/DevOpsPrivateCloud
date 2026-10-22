# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E05.sh — M20-E05 : Synchronisation, santé, dérive et auto-réparation
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API GitLab en GET.

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E05 — Synchronisation, santé, dérive et auto-réparation"
require_cmd jq kubectl

if ! _m20d_peut_lire_argo; then
  skip "Contrôles de l'Application labo" "wb-checks ne lit pas encore les objets d'Argo CD : termine M20-E03"
  return 0
fi

_m20d_e05_app="$(_m20d_app labo)"
check_cmd "Application labo présente" _m20d_json "$_m20d_e05_app" '.kind == "Application"'

# --- 1. Politique de synchronisation ---------------------------------------------------------------
check_cmd "Synchronisation automatique avec auto-réparation (selfHeal)" _m20d_json "$_m20d_e05_app" \
  '.spec.syncPolicy.automated.selfHeal == true and (.spec.syncPolicy.automated.enabled != false)'
check_cmd "Synchronisation automatique avec suppression des objets retirés de Git (prune)" _m20d_json "$_m20d_e05_app" \
  '.spec.syncPolicy.automated.prune == true'
check_cmd "Option ServerSideApply=true" _m20d_json "$_m20d_e05_app" \
  '(.spec.syncPolicy.syncOptions // []) | index("ServerSideApply=true")'
check_cmd "Option CreateNamespace=false écrite (l'espace n'appartient pas à l'application)" _m20d_json "$_m20d_e05_app" \
  '(.spec.syncPolicy.syncOptions // []) | index("CreateNamespace=false")'

# --- 2. Diff côté serveur ---------------------------------------------------------------------------
_m20d_e05_params="$(_m20d_k -n "$_M20D_NS" get configmap argocd-cmd-params-cm -o json)"
_m20d_e05_ssd() {
  _m20d_json "$1" '.data["controller.diff.server.side"] == "true"' ||
    _m20d_json "$2" '.metadata.annotations["argocd.argoproj.io/compare-options"] // "" | test("ServerSideDiff=true")'
}
check_cmd "Diff côté serveur actif (contrôleur, ou annotation de l'Application)" _m20d_e05_ssd "$_m20d_e05_params" "$_m20d_e05_app"
check_output "values d'Argo CD (main de plateforme/k8s) : controller.diff.server.side" 'controller\.diff\.server\.side:[[:space:]]*"?true' \
  _m20d_contenu_main plateforme/k8s composants/argocd/values.yaml

# --- 3. Le cluster est conforme à Git ---------------------------------------------------------------
check_cmd "labo : Synced et Healthy" _m20d_json "$_m20d_e05_app" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
_m20d_e05_dep="$(_m20d_k -n wb-essais get deployment labo -o json)"
_m20d_e05_git="$(_m20d_contenu_main formation/gitops-labo k8s/deployment.yaml | sed -n 's/^  replicas:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1)"
if [[ -z "$_m20d_e05_git" ]]; then
  skip "Réplicas de labo conformes à Git" "replicas illisible dans k8s/deployment.yaml de formation/gitops-labo"
else
  check_cmd "Réplicas de labo = valeur de Git ($_m20d_e05_git), dérives éventuelles corrigées" _m20d_json "$_m20d_e05_dep" \
    '.spec.replicas == ($n | tonumber) and (.status.readyReplicas // 0) == ($n | tonumber)' --arg n "$_m20d_e05_git"
fi
check_cmd "Le Deployment est appliqué en server-side apply par Argo CD (gestionnaire argocd-controller, opération Apply)" \
  _m20d_json "$(_m20d_k -n wb-essais get deployment labo --show-managed-fields -o json)" \
  '[.metadata.managedFields[] | select(.manager == "argocd-controller" and .operation == "Apply")] | length == 1'
check_cmd "Plus d'annotation last-applied-configuration (migration du client-side apply faite)" _m20d_json "$_m20d_e05_dep" \
  '(.metadata.annotations // {}) | has("kubectl.kubernetes.io/last-applied-configuration") | not'
check_cmd "Aucun objet de labo en attente de suppression (requiresPruning)" _m20d_json "$_m20d_e05_app" \
  '[.status.resources[]? | select(.requiresPruning == true)] | length == 0'
# L'historique vit dans l'objet Application : il repart de zéro si l'Application est recréée
# (M20-E06, étape 7). Après la reprise dans Git, le contrôle est donc sans objet.
if [[ "$(_m20d_suivi "$_m20d_e05_app")" == applications:* ]] && ! _m20d_json "$_m20d_e05_app" '[.status.history[]?.revision] | unique | length >= 4'; then
  skip "Historique : au moins 4 révisions déployées (E04, puis l'ajout et le retrait de labo-essai)" "Application recréée depuis plateforme/gitops (M20-E06) : historique remis à zéro"
else
  check_cmd "Historique : au moins 4 révisions déployées (E04, puis l'ajout et le retrait de labo-essai)" _m20d_json "$_m20d_e05_app" \
    '[.status.history[]?.revision] | unique | length >= 4'
fi
check_cmd "La ConfigMap d'essai labo-essai n'existe plus dans wb-essais" _m20d_json \
  "$(_m20d_k -n wb-essais get configmaps -o json)" '.items | length > 0 and ([.[] | select(.metadata.name == "labo-essai")] | length == 0)'
