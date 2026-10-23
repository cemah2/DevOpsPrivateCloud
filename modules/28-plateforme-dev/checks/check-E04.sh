# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E04.sh — M28-E04 : VPA : des requêtes justes
# Lecture seule : Application, Deployments, CRD, webhook, VerticalPodAutoscaler (kube) ; document
# dans plateforme/medisphere (GitLab, GET).

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E04 — VPA : des requêtes justes"
require_cmd jq kubectl curl

_m28d_e04_re='^registry\.par1\.medisphere\.internal/.+/autoscaling/vpa-(recommender|updater|admission-controller):1\.7\.1'

check_cmd "Application Argo CD vpa : Synced et Healthy" _m28d_app_saine vpa
for _m28d_e04_d in vpa-recommender vpa-updater vpa-admission-controller; do
  check_cmd "vpa/$_m28d_e04_d prêt, image de Harbor en 1.7.1" _m28d_deploy_pret vpa "$_m28d_e04_d" "$_m28d_e04_re"
done
check_cmd "webhook du VPA en failurePolicy Ignore (une panne du VPA ne bloque aucun pod)" _m28d_kq \
  '[.webhooks[] | .failurePolicy] | all(. == "Ignore")' mutatingwebhookconfigurations.admissionregistration.k8s.io vpa-webhook-config

# VPA attendus : espace, nom, type de cible.
for _m28d_e04_v in mediagenda-recette:mediagenda:Rollout mediagenda-prod:mediagenda:Rollout \
  medinotif-recette:medinotif:Deployment medinotif-prod:medinotif:Deployment medidoc-recette:medidoc:Deployment; do
  IFS=: read -r _m28d_e04_ns _m28d_e04_n _m28d_e04_k <<<"$_m28d_e04_v"
  check_cmd "$_m28d_e04_ns : VPA $_m28d_e04_n en Off sur le $_m28d_e04_k $_m28d_e04_n" _m28d_kq \
    '.spec.targetRef.kind == $k and .spec.targetRef.name == $n and .spec.updatePolicy.updateMode == "Off"' \
    -n "$_m28d_e04_ns" verticalpodautoscalers.autoscaling.k8s.io "$_m28d_e04_n" -- --arg k "$_m28d_e04_k" --arg n "$_m28d_e04_n"
  check_cmd "$_m28d_e04_ns : le VPA $_m28d_e04_n fournit des recommandations" _m28d_kq \
    '(.status.recommendation.containerRecommendations // []) | length >= 1 and all(.target.cpu != null and .target.memory != null)' \
    -n "$_m28d_e04_ns" verticalpodautoscalers.autoscaling.k8s.io "$_m28d_e04_n"
done

check_cmd "aucun VPA en mode actif hors de wb-essais (mode absent = Recreate, actif)" _m28d_kq \
  '[.items[] | select(.metadata.namespace != "wb-essais" and ((.spec.updatePolicy.updateMode // "Recreate") != "Off"))] | length == 0' \
  verticalpodautoscalers.autoscaling.k8s.io -A
check_cmd "l'essai essai-vpa a été retiré de wb-essais" _m28d_absent verticalpodautoscalers.autoscaling.k8s.io essai-vpa wb-essais
check_cmd "plateforme/medisphere : recommandations-ressources.md (tableaux, essai en place, garde-fous)" \
  _m28d_doc docs/plateforme-dev/recommandations-ressources.md 'lowerBound|upperBound|target' 'InPlaceOrRecreate' 'resizePolicy|resize' 'HPA'
