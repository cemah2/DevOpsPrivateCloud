# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E13.sh — M28-E13 « KEDA en production : zéro, cron, Prometheus, repli » : ScaledObject de recette
# (minimum 0, effectivement descendu à 0 sur 24 h) et de prod (minimum ≥ 1), déclencheurs rabbitmq,
# cron (Europe/Paris) et prometheus, repli et comportement, ni pause ni erreur ; collecte de KEDA et
# alertes ; autoscaling.md. Lecture seule.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

title "M28-E13 — KEDA en production"
require_cmd kubectl jq curl

if _m28p_api_repond; then
  check_cmd "recette : ScaledObject medinotif autorise zéro réplica (minReplicaCount 0)" _m28p_so_ok medinotif-recette \
    '(.spec.minReplicaCount // 0) == 0 and (.spec.cooldownPeriod // null) != null'
  check_cmd "prod : ScaledObject medinotif présent, minimum d'au moins un réplica, pas de retour à 0" _m28p_so_ok medinotif-prod \
    '(.spec.minReplicaCount // 0) >= 1 and ((.spec.idleReplicaCount // 1) != 0)'
  for _m28_e13_ns in medinotif-recette medinotif-prod; do
    check_cmd "$_m28_e13_ns : déclencheurs rabbitmq, cron (Europe/Paris) et prometheus" _m28p_so_ok "$_m28_e13_ns" "$_M28P_SO_TRIGGERS"
    check_cmd "$_m28_e13_ns : repli (fallback) et comportement d'HPA déclarés" _m28p_so_ok "$_m28_e13_ns" "$_M28P_SO_ROBUSTE"
    check_cmd "$_m28_e13_ns : ScaledObject Ready et non en pause" _m28p_so_ok "$_m28_e13_ns" "$_M28P_SO_PRET"
  done
  check_cmd "prod : le déclencheur rabbitmq vise le vhost medinotif-prod" _m28p_so_ok medinotif-prod \
    '[.spec.triggers[] | select(.type == "rabbitmq") | .metadata.vhostName] | index("medinotif-prod") != null'
else
  skip "ScaledObject de recette et de prod" "l'API ne répond pas au compte des checks"
fi

if _m28p_prom_repond; then
  check_cmd "Prometheus collecte l'opérateur KEDA (keda_build_info)" _m28p_prom_vrai 'count(keda_build_info)'
  check_cmd "MédiNotif de recette est descendu à 0 au moins une fois en 24 h" _m28p_prom_vrai \
    'count(min_over_time(kube_deployment_spec_replicas{namespace="medinotif-recette", deployment="medinotif"}[24h]) == 0)'
  _m28_e13_sans_erreur() {
    ! _m28p_prom_vrai 'sum(increase(keda_scaler_detail_errors_total{exported_namespace=~"medinotif-.+"}[10m]))'
  }
  check_cmd "aucune erreur de scaler sur MédiNotif ces 10 dernières minutes" _m28_e13_sans_erreur
  for _m28_e13_a in '^KedaScalerEnErreur$|^Keda.*Erreur' '^Keda.*Pause' '^KedaAbsent$|^Keda.*Absent'; do
    check_cmd "alerte KEDA chargée ($_m28_e13_a)" _m28p_alerte_chargee "$_m28_e13_a"
  done
else
  skip "collecte et alertes de KEDA" "Prometheus ne répond pas"
fi

check_cmd "autoscaling.md (main) : repli, démarrage à froid, procédure de pause" \
  _m28p_doc autoscaling 'fallback|repli' 'froid' 'paused|pause'
