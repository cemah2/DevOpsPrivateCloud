# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E04.sh — M20-E04 : Première Application
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks : Application labo, objets de wb-essais),
# API GitLab en GET.

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E04 — Première Application"
require_cmd jq kubectl

if ! _m20d_peut_lire_argo; then
  skip "Contrôles de l'Application labo" "wb-checks ne lit pas encore les objets d'Argo CD : termine M20-E03 (lab/bin/check 20 03)"
  return 0
fi

# --- 1. Le dépôt ------------------------------------------------------------------------------------
for _m20d_e04_f in k8s/kustomization.yaml k8s/deployment.yaml k8s/service.yaml k8s/configmap.yaml; do
  check_cmd "formation/gitops-labo (main) : $_m20d_e04_f" _m20d_fichier_main formation/gitops-labo "$_m20d_e04_f"
done

# --- 2. L'Application -------------------------------------------------------------------------------
_m20d_e04_app="$(_m20d_app labo)"
check_cmd "Application labo présente dans l'espace argocd" _m20d_json "$_m20d_e04_app" '.kind == "Application"'
_m20d_e04_source() {
  _m20d_meme_depot "$(jq -r '.spec.source.repoURL // ""' <<<"$1")" formation/gitops-labo &&
    _m20d_json "$1" '.spec.source.path == "k8s" and .spec.source.targetRevision == "main"'
}
check_cmd "Source : formation/gitops-labo, branche main, dossier k8s" _m20d_e04_source "$_m20d_e04_app"
check_cmd "Destination : ce cluster, espace wb-essais" _m20d_json "$_m20d_e04_app" \
  '.spec.destination.server == $s and .spec.destination.namespace == "wb-essais"' --arg s "$_M20D_IN_CLUSTER"
check_cmd "Projet default (E04) ou labo (à partir de M20-E07)" _m20d_json "$_m20d_e04_app" \
  '.spec.project == "default" or .spec.project == "labo"'
check_cmd "Synchronisation automatique activée" _m20d_json "$_m20d_e04_app" \
  '(.spec.syncPolicy.automated // null) != null and (.spec.syncPolicy.automated.enabled != false)'
check_cmd "Statut : Synced et Healthy" _m20d_json "$_m20d_e04_app" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
check_cmd "Dernière opération réussie" _m20d_json "$_m20d_e04_app" '.status.operationState.phase == "Succeeded"'
# L'historique vit dans l'objet Application : il repart de zéro si l'Application est recréée
# (M20-E06, étape 7). Après la reprise dans Git, le contrôle est donc sans objet.
if [[ "$(_m20d_suivi "$_m20d_e04_app")" == applications:* ]] && ! _m20d_json "$_m20d_e04_app" '[.status.history[]?.revision] | unique | length >= 2'; then
  skip "Historique : au moins deux révisions déployées (manuelle, puis automatique après un commit)" "Application recréée depuis plateforme/gitops (M20-E06) : historique remis à zéro"
else
  check_cmd "Historique : au moins deux révisions déployées (manuelle, puis automatique après un commit)" _m20d_json "$_m20d_e04_app" \
    '[.status.history[]?.revision] | unique | length >= 2'
fi
_m20d_e04_tete() {
  local dep tete
  dep="$(jq -r '.status.sync.revision // ""' <<<"$1")"
  tete="$(gitlab_api "projects/formation%2Fgitops-labo/repository/branches/main" 2>/dev/null | jq -r '.commit.id // ""')" || true
  [[ -n "$dep" && "$dep" == "$tete" ]]
}
check_cmd "La révision déployée est la dernière de main" _m20d_e04_tete "$_m20d_e04_app"

# --- 3. Les objets dans wb-essais -------------------------------------------------------------------
_m20d_e04_dep="$(_m20d_k -n wb-essais get deployment labo -o json)"
check_cmd "Deployment labo prêt (réplicas demandés = prêts)" _m20d_json "$_m20d_e04_dep" \
  '.spec.replicas >= 1 and (.status.readyReplicas // 0) == .spec.replicas'
_m20d_e04_suivi() { [[ "$(_m20d_suivi "$1")" == "$2" ]]; }
check_cmd "Deployment labo suivi par Argo CD (annotation argocd.argoproj.io/tracking-id de l'Application labo)" \
  _m20d_e04_suivi "$_m20d_e04_dep" "labo:apps/Deployment:wb-essais/labo"
check_cmd "Image de labo tirée par le cache Harbor, version explicite (ni latest, ni sans étiquette)" _m20d_json "$_m20d_e04_dep" \
  '[.spec.template.spec.containers[].image] | length > 0 and all(
     startswith("registry.par1.medisphere.internal/dockerhub/")
     and (test("@sha256:[0-9a-f]{64}$") or (split("/") | last | test(":.+")))
     and (endswith(":latest") | not))'
check_cmd "Service labo : port 80, au moins un point de terminaison prêt" _m20d_json \
  "$(_m20d_k -n wb-essais get endpointslices -l kubernetes.io/service-name=labo -o json)" \
  '[.items[].endpoints[]? | select(.conditions.ready == true)] | length >= 1'
check_cmd "La page servie par labo vient de la ConfigMap labo-page" _m20d_json \
  "$(_m20d_k -n wb-essais get configmap labo-page -o json)" '.data["index.html"] // "" | test("labo")'
