# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E07.sh — M21-E07 : Les métriques de MédiAgenda : ServiceMonitor et PodMonitor
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API de Prometheus, API GitLab.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E07 — Les métriques de MédiAgenda : ServiceMonitor et PodMonitor"
require_cmd jq curl kubectl

# --- 1. Le dépôt plateforme/observabilite et son Application ----------------------------------------
for _m21d_e07_f in kustomization.yaml .gitlab-ci.yml README.md regles/kustomization.yaml scrape/kustomization.yaml; do
  check_cmd "plateforme/observabilite (main) : $_m21d_e07_f" _m21d_fichier_main plateforme/observabilite "$_m21d_e07_f"
done
check_output "plateforme/observabilite : la kustomization racine pose $_M21D_SELECTEUR=oui" \
  'medisphere\.internal/supervision: *"?oui' _m21d_contenu_main plateforme/observabilite kustomization.yaml
check_output "plateforme/observabilite : dernier pipeline de main réussi" '^success$' _m21d_pipeline_main plateforme/observabilite
check_cmd "Application observabilite (projet plateforme) : Synced et Healthy" _m21d_json "$(_m21d_application observabilite)" \
  '.spec.project == "plateforme" and .status.sync.status == "Synced" and .status.health.status == "Healthy"
   and ((.spec.source.repoURL // "") | test("plateforme/observabilite"))'

# --- 2. Côté équipes : components/supervision -------------------------------------------------------
check_cmd "mediagenda/deploiement (main) : components/supervision" \
  _m21d_fichier_main mediagenda/deploiement components/supervision/kustomization.yaml
check_cmd "medidoc/deploiement (main) : components/supervision" \
  _m21d_fichier_main medidoc/deploiement components/supervision/kustomization.yaml

for _m21d_e07_ns in mediagenda-dev mediagenda-recette mediagenda-prod; do
  check_cmd "$_m21d_e07_ns : ServiceMonitor mediagenda étiqueté $_M21D_SELECTEUR=oui, port nommé" _m21d_json \
    "$(_m21d_k -n "$_m21d_e07_ns" get servicemonitors.monitoring.coreos.com mediagenda -o json)" \
    '.metadata.labels[$l] == "oui" and ([.spec.endpoints[] | .port // empty | select(type == "string" and length > 0)] | length >= 1)' \
    --arg l "$_M21D_SELECTEUR"
  # Toutes les cibles du job répondent, et il y en a autant que de pods de l'API prêts.
  _m21d_e07_cibles="$(_m21d_valeur "count(up{job=\"mediagenda\", namespace=\"$_m21d_e07_ns\"} == 1)")"
  _m21d_e07_pods="$(_m21d_k -n "$_m21d_e07_ns" get pods -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -o json \
    | jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || true)"
  if [[ -n "$_m21d_e07_cibles" && -n "$_m21d_e07_pods" && "$_m21d_e07_cibles" -ge 1 && "$_m21d_e07_cibles" -eq "$_m21d_e07_pods" ]]; then
    _ok "$_m21d_e07_ns : $_m21d_e07_cibles cible(s) up{job=\"mediagenda\"}, une par pod prêt de l'API (canary compris)"
  else
    _ko "$_m21d_e07_ns : ${_m21d_e07_cibles:-0} cible(s) up{job=\"mediagenda\"} pour ${_m21d_e07_pods:-?} pod(s) prêt(s) de l'API"
  fi
done
check_cmd "Aucune cible mediagenda ni medidoc en échec" _m21d_vide 'up{job=~"mediagenda|medidoc"} == 0'
check_cmd "Pas de double collecte : une seule série up par pod de l'API" _m21d_vide 'count by (namespace, pod) (up{job="mediagenda"}) > 1'
check_cmd "Métriques applicatives présentes (mediagenda_http_requests_total) dans les trois environnements" \
  _m21d_au_moins 'count(count by (namespace) (mediagenda_http_requests_total))' 3
check_cmd "medidoc-dev : cible up{job=\"medidoc\"} qui répond" _m21d_au_moins 'count(up{job="medidoc", namespace="medidoc-dev"} == 1)' 1
check_cmd "PodMonitor mediagenda-db en recette, étiqueté $_M21D_SELECTEUR=oui" _m21d_json \
  "$(_m21d_k -n mediagenda-recette get podmonitors.monitoring.coreos.com mediagenda-db -o json)" \
  '.metadata.labels[$l] == "oui"' --arg l "$_M21D_SELECTEUR"
check_cmd "Instances PostgreSQL de mediagenda-recette collectées (job mediagenda-db, cnpg_collector_up = 1)" \
  _m21d_au_moins 'count(cnpg_collector_up{namespace="mediagenda-recette"} == 1)' 1

# --- 3. Le flux réseau ------------------------------------------------------------------------------
check_cmd "Politique de collecte (Cilium, toute la plateforme) : Prometheus de supervision vers les espaces d'équipe" _m21d_json \
  "$(_m21d_k get ciliumclusterwidenetworkpolicies -o json)" \
  '[.items[] | select([.spec.ingress[]?.fromEndpoints[]?.matchLabels["io.kubernetes.pod.namespace"]] | index("supervision") != null)]
   | length >= 1'
