# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F1-S10 « Laisser Argo CD reconstruire la plateforme ».
# Lecture seule : Applications d'Argo CD (wb-checks-livraison), objets des services (wb-checks-services,
# wb-checks-securite, wb-checks-observabilite), Prometheus/Thanos, Alertmanager, Grafana, Loki,
# API de gestion de RabbitMQ (compte monitoring des checks).
#
# Variable : WB_F1_S10_ATTENTE (« mediagenda-recette mediagenda-prod portail ») : Applications qui
# peuvent attendre leurs données (S11) ; elles doivent exister, pas être saines.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S10 — Laisser Argo CD reconstruire la plateforme"
require_cmd kubectl jq curl

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi

read -r -a _f1_s10_attente <<<"${WB_F1_S10_ATTENTE:-mediagenda-recette mediagenda-prod portail}"

# --- Argo CD ---------------------------------------------------------------------------------------
check_cmd "application racine présente (racine, projet plateforme)" _f1c_kq '.spec.project == "plateforme"' \
  -n argocd applications.argoproj.io racine
for _f1_s10_a in projets plateforme applications; do
  check_cmd "Application de groupe $_f1_s10_a : Synced et Healthy" _f1c_app_saine "$_f1_s10_a"
done
_f1_s10_nb="$(_f1c_nb applications.argoproj.io -n argocd)"
check_cmd "au moins 30 Applications reconstruites ($_f1_s10_nb)" test "$_f1_s10_nb" -ge 30
_f1_s10_ko="$(_f1c_apps_non_saines "${_f1_s10_attente[@]}" | head -n 6 | paste -sd ' ' -)"
check_cmd "toutes les Applications Synced/Healthy hors attente des données${_f1_s10_ko:+ — $_f1_s10_ko}" \
  test -z "$_f1_s10_ko" -a "$_f1_s10_nb" -gt 0
for _f1_s10_a in "${_f1_s10_attente[@]}"; do
  check_cmd "Application $_f1_s10_a présente (ses données arrivent en S11)" _f1c_kq '.metadata.name != null' \
    -n argocd applications.argoproj.io "$_f1_s10_a"
done

# --- Observabilité ------------------------------------------------------------------------------------
check_cmd "Prometheus (vue globale Thanos) répond" bash -c '[[ -n "$1" ]]' _ "$(_f1c_prom_val 'count(up)')"
_f1_s10_hist="$(_f1c_prom_val 'count(up offset 3d)')"
check_cmd "historique d'avant la reconstruction lisible (séries de il y a 3 jours dans Thanos : ${_f1_s10_hist:-aucune})" \
  bash -c '[[ "$1" =~ ^[0-9.]+$ ]] && awk -v v="$1" "BEGIN { exit !(v > 0) }"' _ "${_f1_s10_hist:-}"
check_cmd "Alertmanager répond (et l'alerte Watchdog est active)" \
  bash -c 'jq -e "any(.[]; .labels.alertname == \"Watchdog\")" <<<"$1" >/dev/null' _ "$(am_api 'alerts?active=true' 2>/dev/null || echo '[]')"
check_cmd "Grafana répond (compte des checks)" grafana_api health
check_cmd "Loki répond (étiquettes du locataire plateforme)" loki_api labels plateforme

# --- Sécurité ------------------------------------------------------------------------------------------
for _f1_s10_ns in kyverno falco tetragon kubelet-csr-approver; do
  check_cmd "espace $_f1_s10_ns : charges prêtes" _f1c_espace_pret "$_f1_s10_ns"
done
if _f1c_peut list certificatesigningrequests.certificates.k8s.io; then
  check_cmd "aucune demande de certificat de kubelet en attente" _f1c_kq \
    '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving" and ((.status.conditions // []) | length == 0))] | length == 0' \
    certificatesigningrequests.certificates.k8s.io
else
  skip "demandes de certificats de kubelet" "le compte des checks ne lit pas les CSR"
fi

# --- Services des blocs G -------------------------------------------------------------------------------
for _f1_s10_ns in keda vpa capsule-system rabbitmq-system messagerie k6 chaos-mesh; do
  check_cmd "espace $_f1_s10_ns : charges prêtes" _f1c_espace_pret "$_f1_s10_ns"
done
if _f1c_lit tenants.capsule.clastix.io; then
  check_cmd "Capsule : locataires mediagenda, medidoc, medinotif" _f1c_kq \
    '[.items[].metadata.name] as $t | all(["mediagenda", "medidoc", "medinotif"][]; . as $n | $t | index($n))' tenants.capsule.clastix.io
else
  skip "locataires Capsule" "CRD absente ou illisible par le compte des checks"
fi
_f1_s10_rmq="$(rabbitmq_api nodes 2>/dev/null || true)"
check_cmd "RabbitMQ : trois nœuds en service" jq -e '[.[] | select(.running == true)] | length == 3' <<<"${_f1_s10_rmq:-[]}"
