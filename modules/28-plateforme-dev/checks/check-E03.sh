# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
#
# check-E03.sh — M28-E03 : KEDA : MédiNotif suit sa file
# Lecture seule : Application, Deployments, APIService, ClusterRole, objets de topologie RabbitMQ
# (rabbitmq.com), ScaledObject, TriggerAuthentication, ExternalSecret, HPA (kube) ; métriques de KEDA et
# de kube-state-metrics (Prometheus). Aucun Secret lu. Rejouable après M28-E13 (zéro en recette).
#
# Variable de lab/lab.env (facultative) : WB_M28_APP_MEDINOTIF_RECETTE (défaut : medinotif-recette),
# nom de l'Application Argo CD générée par l'ApplicationSet medinotif (M27).

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E03 — KEDA : MédiNotif suit sa file"
require_cmd jq kubectl curl

_m28d_e03_ns=medinotif-recette
_m28d_e03_re_keda='^registry\.par1\.medisphere\.internal/.+/kedacore/keda(-metrics-apiserver|-admission-webhooks)?:2\.21\.[0-9]+'

# --- 1. KEDA ---------------------------------------------------------------------------------------------
check_cmd "Application Argo CD keda : Synced et Healthy" _m28d_app_saine keda
for _m28d_e03_d in keda-operator keda-operator-metrics-apiserver keda-admission-webhooks; do
  check_cmd "keda/$_m28d_e03_d prêt, image de Harbor en 2.21" _m28d_deploy_pret keda "$_m28d_e03_d" "$_m28d_e03_re_keda"
done
check_cmd "APIService v1beta1.external.metrics.k8s.io servie par keda/keda-operator-metrics-apiserver, disponible" _m28d_kq \
  '.spec.service.namespace == "keda" and .spec.service.name == "keda-operator-metrics-apiserver"
   and ([.status.conditions[]? | select(.type == "Available" and .status == "True")] | length == 1)' \
  apiservices.apiregistration.k8s.io v1beta1.external.metrics.k8s.io

# --- 2. Droits des checks --------------------------------------------------------------------------------
check_cmd "ClusterRole wb-checks-services-m28 : agrégée, KEDA/VPA/Capsule en lecture, aucun droit sur les Secrets" _m28d_kq \
  '.metadata.labels["workbook.medisphere.internal/checks"] == "true"
   and ([.rules[].apiGroups[]] | (index("keda.sh") != null and index("autoscaling.k8s.io") != null and index("capsule.clastix.io") != null))
   and ([.rules[] | select((.resources // []) | index("secrets") != null)] | length == 0)' \
  clusterroles.rbac.authorization.k8s.io wb-checks-services-m28

# --- 3. Compte de KEDA sur RabbitMQ (topologie déclarative, espace messagerie) --------------------------
check_cmd "RabbitMQ : utilisateur keda-recette déclaré, étiquette management (ni administrator ni monitoring)" _m28d_kq \
  '[.items[] | select(.metadata.name == "keda-recette") | (.spec.tags // []) | (index("management") != null and index("administrator") == null and index("monitoring") == null)] | any' \
  -n messagerie users.rabbitmq.com
check_cmd "RabbitMQ : permissions de keda-recette sur medinotif-recette sans pouvoir sur les messages (motifs ^$)" _m28d_kq \
  '[.items[] | select(.spec.vhost == "medinotif-recette" and ((.spec.userReference.name // "") == "keda-recette" or (.spec.user // "") == "keda-recette"))
    | .spec.permissions | (.configure == "^$" and .write == "^$" and .read == "^$")] | (length >= 1 and all)' \
  -n messagerie permissions.rabbitmq.com

# --- 4. MédiNotif de recette ------------------------------------------------------------------------------
check_cmd "ScaledObject medinotif prêt (condition Ready)" _m28d_kq \
  '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 1' \
  -n "$_m28d_e03_ns" scaledobjects.keda.sh medinotif
check_cmd "ScaledObject : déclencheur rabbitmq, protocole http, file notifications du vhost medinotif-recette" _m28d_kq \
  '[.spec.triggers[] | select(.type == "rabbitmq" and .metadata.queueName == "notifications"
     and .metadata.vhostName == "medinotif-recette" and (.metadata.protocol // "auto") == "http")] | length >= 1' \
  -n "$_m28d_e03_ns" scaledobjects.keda.sh medinotif
check_cmd "ScaledObject : authentification par medinotif-rabbitmq, aucun identifiant dans ses métadonnées" _m28d_kq \
  '[.spec.triggers[] | select(.type == "rabbitmq")] | all(.authenticationRef.name == "medinotif-rabbitmq"
     and ((.metadata.host // "") | test("@") | not) and (.metadata | has("password") | not))' \
  -n "$_m28d_e03_ns" scaledobjects.keda.sh medinotif
check_cmd "ScaledObject : bornes écrites (minReplicaCount et maxReplicaCount déclarés, max ≥ 2)" _m28d_kq \
  '(.spec | has("minReplicaCount") and has("maxReplicaCount")) and .spec.maxReplicaCount >= 2' \
  -n "$_m28d_e03_ns" scaledobjects.keda.sh medinotif
check_cmd "TriggerAuthentication medinotif-rabbitmq : uniquement des références au Secret medinotif-rabbitmq" _m28d_kq \
  '((.spec.secretTargetRef // []) | length >= 2) and all(.spec.secretTargetRef[]; .name == "medinotif-rabbitmq")
   and ([.spec.secretTargetRef[].parameter] | index("password") != null)' \
  -n "$_m28d_e03_ns" triggerauthentications.keda.sh medinotif-rabbitmq
check_cmd "ExternalSecret medinotif-rabbitmq synchronisé depuis OpenBao" _m28d_kq \
  '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 1' \
  -n "$_m28d_e03_ns" externalsecrets.external-secrets.io medinotif-rabbitmq
check_cmd "HPA keda-hpa-medinotif créé par KEDA (métrique externe)" _m28d_kq \
  '[.spec.metrics[]? | select(.type == "External")] | length >= 1' \
  -n "$_m28d_e03_ns" horizontalpodautoscalers.autoscaling keda-hpa-medinotif
check_cmd "Argo CD ne possède plus spec.replicas du Deployment medinotif" \
  _m28d_replicas_hors_argocd "$_m28d_e03_ns" deployments.apps medinotif
check_cmd "Application ${WB_M28_APP_MEDINOTIF_RECETTE:-medinotif-recette} : Synced" \
  _m28d_app_synced "${WB_M28_APP_MEDINOTIF_RECETTE:-medinotif-recette}"

# --- 5. Il a vraiment travaillé -----------------------------------------------------------------------------
check_cmd "KEDA lit la file (keda_scaler_metrics_value présente pour medinotif-recette)" _m28d_prom_positif \
  'count(keda_scaler_metrics_value{namespace="medinotif-recette", scaledObject="medinotif"})'
check_cmd "l'HPA de KEDA a demandé au moins 2 pods dans les dernières 24 h (essai de rafale)" _m28d_prom_positif \
  'max_over_time(kube_horizontalpodautoscaler_status_desired_replicas{namespace="medinotif-recette", horizontalpodautoscaler="keda-hpa-medinotif"}[24h]) >= 2'
check_cmd "aucune erreur du scaler sur l'heure écoulée (keda_scaler_detail_errors_total)" _m28d_prom_nul \
  'sum(increase(keda_scaler_detail_errors_total{namespace="medinotif-recette", scaledObject="medinotif"}[1h]))
   or on() (0 * count(keda_scaler_metrics_value{namespace="medinotif-recette", scaledObject="medinotif"}))'
