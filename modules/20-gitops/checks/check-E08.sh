# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E08.sh — M20-E08 : Reprendre MédiAgenda dev sous Argo CD sans coupure
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks : Application, Deployment, ReplicaSets,
# Cluster CNPG ; GET /sante par le mandataire de l'API), API GitLab en GET (pipelines, jobs).

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E08 — Reprendre MédiAgenda dev sous Argo CD sans coupure"
require_cmd jq kubectl date

if ! _m20d_peut_lire_argo; then
  skip "Contrôles de l'Application mediagenda-dev" "wb-checks ne lit pas encore les objets d'Argo CD : termine M20-E03"
  return 0
fi

_m20d_e08_ns=mediagenda-dev
_m20d_e08_app="$(_m20d_app mediagenda-dev)"
# Après M20-E10, l'Application est créée par l'ApplicationSet « mediagenda » : même nom, contrôles valables.

# --- 1. L'Application -------------------------------------------------------------------------------
check_cmd "Application mediagenda-dev présente, projet mediagenda" _m20d_json "$_m20d_e08_app" '.spec.project == "mediagenda"'
_m20d_e08_source() {
  _m20d_meme_depot "$(jq -r '.spec.source.repoURL // ""' <<<"$1")" mediagenda/deploiement &&
    _m20d_json "$1" '.spec.source.path == "overlays/dev" and .spec.source.targetRevision == "main"'
}
check_cmd "Source : mediagenda/deploiement, main, overlays/dev" _m20d_e08_source "$_m20d_e08_app"
check_cmd "Destination : ce cluster, espace mediagenda-dev" _m20d_json "$_m20d_e08_app" \
  '.spec.destination.server == $s and .spec.destination.namespace == "mediagenda-dev"' --arg s "$_M20D_IN_CLUSTER"
check_cmd "Options : ServerSideApply=true et CreateNamespace=false" _m20d_json "$_m20d_e08_app" \
  '(.spec.syncPolicy.syncOptions // []) as $o | ($o | index("ServerSideApply=true")) and ($o | index("CreateNamespace=false"))'
check_cmd "Synchronisation automatique (prune, selfHeal) activée après la reprise" _m20d_json "$_m20d_e08_app" \
  '.spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true'
check_cmd "Statut : Synced et Healthy" _m20d_json "$_m20d_e08_app" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'

# --- 2. Aucun pod recréé par la reprise -------------------------------------------------------------
_m20d_e08_info() { jq -r --arg n "$2" '[.spec.info[]? | select(.name == $n) | .value][0] // ""' <<<"$1" 2>/dev/null || true; }
_m20d_e08_quand="$(_m20d_e08_info "$_m20d_e08_app" reprise)"
_m20d_e08_rev="$(_m20d_e08_info "$_m20d_e08_app" revision-avant-reprise)"
_m20d_e08_dep="$(_m20d_k -n "$_m20d_e08_ns" get deployment mediagenda -o json)"
_m20d_e08_rev_now="$(jq -r '.metadata.annotations["deployment.kubernetes.io/revision"] // ""' <<<"$_m20d_e08_dep" 2>/dev/null || true)"
if [[ -z "$_m20d_e08_quand" || -z "$_m20d_e08_rev" ]]; then
  _ko "Reprise consignée dans l'Application (spec.info : « reprise » et « revision-avant-reprise »)"
elif ! _m20d_e08_epoch="$(date -d "$_m20d_e08_quand" +%s 2>/dev/null)"; then
  _ko "spec.info « reprise » illisible ($_m20d_e08_quand) : date ISO 8601 attendue, ex. 2026-10-23T09:40:00Z"
elif [[ "$_m20d_e08_rev_now" != "$_m20d_e08_rev" ]]; then
  skip "Aucun ReplicaSet créé par la reprise" "une nouvelle version a été livrée depuis (révision $_m20d_e08_rev_now, reprise faite en $_m20d_e08_rev) : contrôle sans objet"
else
  _ok "Reprise consignée : $_m20d_e08_quand, révision $_m20d_e08_rev du Deployment"
  _m20d_e08_rs="$(_m20d_k -n "$_m20d_e08_ns" get replicasets -o json)"
  check_cmd "Le ReplicaSet de la révision $_m20d_e08_rev a été créé AVANT la reprise (pas de nouveau déploiement)" \
    _m20d_json "$_m20d_e08_rs" \
    '[.items[] | select(.metadata.annotations["deployment.kubernetes.io/revision"] == $r
                        and (.metadata.ownerReferences // [] | any(.name == "mediagenda")))]
     | length == 1 and ((.[0].metadata.creationTimestamp | fromdateiso8601) < ($t | tonumber))' \
    --arg r "$_m20d_e08_rev" --arg t "$_m20d_e08_epoch"
fi

# --- 3. Les objets sont adoptés ---------------------------------------------------------------------
_m20d_e08_suivi() { [[ "$(_m20d_suivi "$1")" == "$2" ]]; }
check_cmd "Deployment mediagenda suivi par mediagenda-dev (annotation de suivi)" \
  _m20d_e08_suivi "$_m20d_e08_dep" "mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda"
check_cmd "Argo CD gère les champs du Deployment (gestionnaire argocd-controller, Apply)" _m20d_json \
  "$(_m20d_k -n "$_m20d_e08_ns" get deployment mediagenda --show-managed-fields -o json)" \
  '[.metadata.managedFields[] | select(.manager == "argocd-controller" and .operation == "Apply")] | length == 1'
_m20d_e08_db="$(_m20d_k -n "$_m20d_e08_ns" get clusters.postgresql.cnpg.io mediagenda-db -o json)"
check_cmd "Base mediagenda-db protégée : Prune=false et Delete=false" _m20d_json "$_m20d_e08_db" \
  '.metadata.annotations["argocd.argoproj.io/sync-options"] // "" | (test("Prune=false") and test("Delete=false"))'
check_cmd "Base mediagenda-db suivie par mediagenda-dev" \
  _m20d_e08_suivi "$_m20d_e08_db" "mediagenda-dev:postgresql.cnpg.io/Cluster:mediagenda-dev/mediagenda-db"
check_cmd "Pas de finaliseur de suppression en cascade sur mediagenda-dev" _m20d_json "$_m20d_e08_app" \
  '(.metadata.finalizers // []) | index("resources-finalizer.argocd.argoproj.io") | not'
check_cmd "MédiAgenda dev répond (GET /sante par le Service)" _m20d_json \
  "$(_m20d_k get --raw "/api/v1/namespaces/$_m20d_e08_ns/services/mediagenda:http/proxy/sante")" '.statut == "ok"'

# --- 4. La CI n'écrit plus dans mediagenda-dev ------------------------------------------------------
_m20d_e08_jobs() {
  local pid
  pid="$(gitlab_api "projects/mediagenda%2Fdeploiement/pipelines?ref=main&per_page=1" 2>/dev/null | jq -r '.[0].id // ""')" || true
  [[ -n "$pid" ]] || return 1
  gitlab_api "projects/mediagenda%2Fdeploiement/pipelines/$pid/jobs?per_page=100" 2>/dev/null
}
_m20d_e08_jobs_json="$(_m20d_e08_jobs || true)"
if [[ -z "$_m20d_e08_jobs_json" ]]; then
  _ko "Dernier pipeline de main de mediagenda/deploiement illisible (aucun pipeline ?)"
else
  check_cmd "Dernier pipeline de main de mediagenda/deploiement : plus de job deployer-dev" _m20d_json "$_m20d_e08_jobs_json" \
    'length > 0 and ([.[] | select(.name == "deployer-dev")] | length == 0)'
fi
check_output "Procédure de reprise écrite (plateforme/medisphere, docs/livraison/gitops/reprise-sans-coupure.md)" 'ReplicaSet' \
  _m20d_contenu_main plateforme/medisphere docs/livraison/gitops/reprise-sans-coupure.md
