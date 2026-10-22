# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E02.sh — M22-E02 : Loki multi-locataire sur le RGW
# À lancer depuis adm01. Lecture seule : Application Argo CD et objets de l'espace journaux (« kube »),
# API de Loki par 10.10.41.62:3100 (GET), liste des objets du compartiment (s3-loki.env), sources de
# Grafana (ConfigMap et réglages visibles d'un Viewer), fichiers sur main (GitLab).

# shellcheck source=_m22-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-decouverte.sh"

title "M22-E02 — Loki multi-locataire sur le RGW"
require_cmd jq kubectl curl

# --- 1. Application et pods ---------------------------------------------------------------------------
_m22d_e02_app="$(_m22d_app loki)"
check_cmd "Application Argo CD loki : projet plateforme, destination journaux" _m22d_json "$_m22d_e02_app" \
  '.spec.project == "plateforme" and .spec.destination.namespace == "journaux"'
check_cmd "Application loki : chart tiré de Harbor (charts/), version 19.x" _m22d_json "$_m22d_e02_app" \
  'any((.spec.sources // [.spec.source])[]; (.repoURL | test("registry\\.par1\\.medisphere\\.internal/charts")) and .chart == "loki" and (.targetRevision | startswith("19.")))'
check_cmd "Application loki : synchronisée et saine" _m22d_json "$_m22d_e02_app" "$_M22D_APP_SAINE"

_m22d_e02_sts="$(_m22d_k get statefulsets -n "$_M22D_NS" -o json)"
check_cmd "StatefulSet Loki en mode monolithique (cible all), prêt" _m22d_json "$_m22d_e02_sts" \
  'any(.items[]; (.spec.template.spec.containers[] | select(.name == "loki") | .args | index("-target=all"))
     and (.status.readyReplicas // 0) >= 1)'
check_cmd "Loki : WAL sur un volume ceph-rbd (volumeClaimTemplates)" _m22d_json "$_m22d_e02_sts" \
  'any(.items[]; any(.spec.volumeClaimTemplates[]?; .spec.storageClassName == "ceph-rbd"))'
check_cmd "Loki : identifiants S3 par Secret loki-objstore (pas en clair dans les values)" _m22d_json "$_m22d_e02_sts" \
  'any(.items[]; any(.spec.template.spec.containers[] | select(.name == "loki") | .envFrom[]?; .secretRef.name == "loki-objstore"))'
check_cmd "Ni passerelle nginx, ni memcached, ni canari dans journaux" _m22d_json \
  "$(_m22d_k get deployments,statefulsets,daemonsets -n "$_M22D_NS" -o json)" \
  '[.items[] | select(.metadata.name | test("gateway|memcached|chunks-cache|results-cache|canary"))] | length == 0'

# --- 2. Service externe et politique réseau -------------------------------------------------------------
_m22d_e02_svc="$(_m22d_k get services -n "$_M22D_NS" -o json)"
check_cmd "Service LoadBalancer d'adresse 10.10.41.62, port 3100 seul, externalTrafficPolicy Local" _m22d_json "$_m22d_e02_svc" \
  'any(.items[]; .spec.type == "LoadBalancer" and .spec.externalTrafficPolicy == "Local"
     and ([.status.loadBalancer.ingress[]?.ip] | index($ip)) != null
     and ([.spec.ports[].port] == [3100]))' --arg ip "$_M22D_LOKI_IP"
check_dns "loki.apps.par1.medisphere.internal → 10.10.41.62" loki.apps.par1.medisphere.internal A '^10\.10\.41\.62$'
check_cmd "CiliumNetworkPolicy sur les pods Loki dans journaux" _m22d_json \
  "$(_m22d_k get ciliumnetworkpolicies.cilium.io -n "$_M22D_NS" -o json)" \
  'any(.items[]; .spec.endpointSelector.matchLabels["app.kubernetes.io/name"] == "loki" and (.spec.ingress | length) >= 3)'

# --- 3. API de Loki ----------------------------------------------------------------------------------------
check_output "API de Loki joignable depuis MGMT (/loki/api/v1/status/buildinfo : version 3.7)" '"version" *: *"3\.7\.' \
  loki_api status/buildinfo
check_http "Loki prêt (/ready)" "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/ready" 200
check_http "multi-locataire : une requête SANS en-tête X-Scope-OrgID est refusée (401)" \
  "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/loki/api/v1/labels" 401
_m22d_e02_cfg="$(curl -sf --max-time "$WB_TIMEOUT" "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/config" 2>/dev/null || true)"
if [[ -n "$_m22d_e02_cfg" ]]; then
  check_output "configuration effective : authentification multi-locataire active" '^auth_enabled: true' printf '%s' "$_m22d_e02_cfg"
  check_output "configuration effective : schéma v13, index tsdb" 'schema: v13' printf '%s' "$_m22d_e02_cfg"
  check_output "configuration effective : compartiment loki-k8s-par1" 'bucketnames: loki-k8s-par1' printf '%s' "$_m22d_e02_cfg"
else
  skip "configuration effective (/config)" "point /config non joignable depuis adm01 : vérifie la CNP loki-entree (MGMT)"
fi

# --- 4. Stockage objet -----------------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  skip "objets dans le compartiment loki-k8s-par1" "AWS CLI absente de adm01 (M16) : installe-la pour ce contrôle"
elif [[ ! -r "$_M22D_S3_ENV" ]]; then
  skip "objets dans le compartiment loki-k8s-par1" "$_M22D_S3_ENV illisible (identifiants de l'utilisateur RGW loki, 600)"
else
  check_cmd "s3-loki.env en mode 600" bash -c '[[ "$(stat -c %a "$1")" == 600 ]]' _ "$_M22D_S3_ENV"
  _m22d_e02_cles="$(_m22d_s3_cles index/)"
  _m22d_e02_age="$(_m22d_age_min "$_M22D_NS" app.kubernetes.io/name=loki)"
  if [[ -n "$_m22d_e02_cles" ]]; then
    _ok "compartiment loki-k8s-par1 : index TSDB envoyé (index/…)"
  elif [[ -n "$_m22d_e02_age" && "$_m22d_e02_age" -lt 120 ]]; then
    skip "compartiment loki-k8s-par1 : index TSDB" "Loki tourne depuis ${_m22d_e02_age} min : l'index et les chunks partent par lots (jusqu'à 2 h), relance plus tard"
  else
    _ko "compartiment loki-k8s-par1 : aucun objet index/ (identifiants, CA du RGW, ou rien n'a été ingéré ?)"
  fi
fi

# --- 5. Sources de données de Grafana ----------------------------------------------------------------------
_m22d_e02_cm="$(_m22d_k get configmaps -n supervision -l grafana_datasource=1 -o json)"
# À partir de M22-E16, « Loki — audit » quitte ce provisionnement (deleteDatasources) et vit dans
# l'organisation Grafana « Sécurité » (OpenTofu, même UID loki-audit) : elle n'est plus attendue ici.
_m22d_e02_attendus=("${_M22D_LOCATAIRES[@]}")
if jq -r '.items[].data[]' <<<"${_m22d_e02_cm:-{\}}" 2>/dev/null | grep -A4 'deleteDatasources:' | grep -q 'Loki — audit'; then
  _m22d_e02_attendus=(plateforme mediagenda medidoc)
  _ok "source « Loki — audit » retirée du provisionnement de l'organisation principale (M22-E16 : organisation Sécurité)"
fi
for _m22d_e02_t in "${_m22d_e02_attendus[@]}"; do
  check_cmd "source Grafana du locataire $_m22d_e02_t déclarée par code (en-tête X-Scope-OrgID)" bash -c '
    jq -r ".items[].data[]" <<<"$1" 2>/dev/null | grep -A12 -E "uid: *loki-$2\$" | grep -Eq "httpHeaderValue1: *$2\$"' \
    _ "$_m22d_e02_cm" "$_m22d_e02_t"
done
_m22d_e02_reg="$(grafana_api frontend/settings 2>/dev/null || true)"
if [[ -n "$_m22d_e02_reg" ]]; then
  _m22d_e02_uids="$(printf 'loki-%s\n' "${_m22d_e02_attendus[@]}" | jq -R . | jq -sc .)"
  check_cmd "Grafana a chargé les sources Loki attendues dans l'organisation principale (${_m22d_e02_attendus[*]})" _m22d_json "$_m22d_e02_reg" \
    '[.datasources[]? | select(.type == "loki") | .uid] as $u | $attendus | all(. as $x | $u | index($x))' \
    --argjson attendus "$_m22d_e02_uids"
else
  skip "sources chargées par Grafana" "API de Grafana injoignable avec le jeton des checks (grafana-checks.token, M21-E05)"
fi
check_cmd "plateforme/observabilite (main) : loki/values.yaml" _m22d_fichier_main "$_M22D_P_OBS" loki/values.yaml
_m22d_e02_arbre="$(gitlab_api "$_M22D_P_GITOPS/repository/tree?ref=main&recursive=true&per_page=100&path=plateforme" 2>/dev/null || true)"
check_cmd "plateforme/gitops (main) : Application loki dans plateforme/" _m22d_json "$_m22d_e02_arbre" \
  '[.[].path] | any(test("^plateforme/.*loki"))'
