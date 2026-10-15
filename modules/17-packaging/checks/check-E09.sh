# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E09.sh — M17-E09 « Kustomize avancé » : production créée par le code, version cohérente,
# recette sur le rendu 0.5.0, dépôt organisé en components. Lecture seule.

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E09 — Kustomize avancé : components, remplacements, générateurs"
require_cmd jq kubectl curl

# --- Espace de production ---
_e09_ns="$(kube get namespace mediagenda-prod -o json 2>/dev/null)" || _e09_ns=""
check_cmd "mediagenda-prod : Pod Security restricted (enforce)" _m17d_jq "$_e09_ns" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
check_cmd "mediagenda-prod : étiquette medisphere.internal/exposition=oui" _m17d_jq "$_e09_ns" \
  '.metadata.labels["medisphere.internal/exposition"] == "oui"'
check_cmd "mediagenda-prod : étiquette medisphere.internal/equipe (politique d'images du M14-E18)" _m17d_jq "$_e09_ns" \
  '.metadata.labels["medisphere.internal/equipe"] == "mediagenda"'
check_cmd "mediagenda-prod : un ResourceQuota" _m17d_jq "$(_m17d_liste mediagenda-prod resourcequota)" '.items | length > 0'
check_cmd "mediagenda-prod : une LimitRange" _m17d_jq "$(_m17d_liste mediagenda-prod limitrange)" '.items | length > 0'
check_cmd "mediagenda-prod : politique de refus par défaut (entrée et sortie, tous les pods)" \
  _m17d_jq "$(_m17d_liste mediagenda-prod networkpolicy)" \
  '[.items[] | select((.spec.podSelector // {}) == {} and ((.spec.policyTypes // []) | index("Ingress") and index("Egress"))
     and ((.spec.ingress // []) | length == 0) and ((.spec.egress // []) | length == 0))] | length > 0'

# --- Application de production ---
_e09_d="$(_m17d_obj mediagenda-prod deploy mediagenda)"
_e09_app() { _m17d_hors_helm "$_e09_d" && _m17d_pret "$_e09_d" 3; }
check_cmd "prod : Deployment mediagenda hors Helm, 3 réplicas prêts" _e09_app
_e09_noeuds() {
  local n
  n="$(_m17d_liste mediagenda-prod pod 'app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api' \
      | jq -r '[.items[] | select(.status.phase == "Running") | .spec.nodeName] | unique | length' 2>/dev/null)" || n=0
  (( n >= 2 ))
}
check_cmd "prod : pods de l'API répartis sur au moins deux nœuds" _e09_noeuds
check_cmd "prod : base mediagenda-db à 3 instances prêtes" _m17d_jq "$(_m17d_obj mediagenda-prod cluster.postgresql.cnpg.io mediagenda-db)" \
  '.spec.instances >= 3 and (.status.readyInstances // 0) >= 3'
check_cmd "prod : Valkey prêt" _m17d_pret "$(_m17d_obj mediagenda-prod statefulset valkey)"
check_cmd "prod : aucun MEDIAGENDA_LOG_LEVEL=DEBUG" _m17d_jq "$_e09_d" \
  '[.spec.template.spec.containers[].env[]? | select(.name == "MEDIAGENDA_LOG_LEVEL" and .value == "DEBUG")] | length == 0'
_e09_tag="$(jq -r '.spec.template.spec.containers[] | select(.name == "api") | .image | sub(".*:"; "")' <<<"$_e09_d" 2>/dev/null)" || _e09_tag=""
check_cmd "prod : étiquette d'image (${_e09_tag:-?}) = MEDIAGENDA_VERSION = app.kubernetes.io/version" _m17d_jq "$_e09_d" \
  "(.spec.template.spec.containers[] | select(.name == \"api\") | .env[] | select(.name == \"MEDIAGENDA_VERSION\") | .value) == \"$_e09_tag\"
   and .metadata.labels[\"app.kubernetes.io/version\"] == \"$_e09_tag\" and \"$_e09_tag\" != \"\""
check_cmd "https://mediagenda.$_m17d_domaine/sante répond 200 avec la version ${_e09_tag:-?}" \
  _m17d_sante "https://mediagenda.$_m17d_domaine/sante" "$_e09_tag"

# --- Recette sur le rendu 0.5.0 ---
_e09_r="$(_m17d_obj mediagenda-recette deploy mediagenda)"
_e09_recette() {
  _m17d_hors_helm "$_e09_r" && _m17d_jq "$_e09_r" '[.spec.template.spec.initContainers[]?.name] | index("migrations") != null'
}
check_cmd "recette : conteneur d'initialisation migrations, toujours hors Helm" _e09_recette

# --- Dépôt ---
check_output "mediagenda/deploiement (main) : chart.env avec un digest" '^CHART_DIGEST=sha256:[a-f0-9]{64}$' \
  _m17d_gl_fichier mediagenda/deploiement chart.env
check_cmd "mediagenda/deploiement (main) : outils/rendre-base.sh" _m17d_gl_existe mediagenda/deploiement outils/rendre-base.sh
for _e09_c in dependances haute-disponibilite debogage livraison; do
  check_output "components/$_e09_c : kind: Component" '^kind:[[:space:]]*Component' \
    _m17d_gl_fichier mediagenda/deploiement "components/$_e09_c/kustomization.yaml"
done
check_cmd "Harbor : charts/mediagenda:0.5.0 publié et signé" _m17d_harbor_signe mediagenda 0.5.0
