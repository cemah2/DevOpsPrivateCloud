# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M18-E18 « Un cluster de recette éphémère en temps limité » (à lancer à T4, avant T5).
# Lecture seule : cluster recette-mediagenda (kubeconfig de ~/.config/workbook/m18/, releases Helm lues avec
# ce kubeconfig : helm list), Helmfile de plateforme/k8s et chart.env de mediagenda/deploiement sur main,
# /sante en HTTP depuis adm01. Aucune valeur de Secret n'est lue (seule l'existence de harbor-pull).

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E18 — Cluster de recette éphémère"
require_cmd kubectl helm jq curl

_e18_kc="$_M18P_KC_RECETTE"
_e18_url="${WB_M18_RECETTE_URL:-http://m18-dev01.par1.medisphere.internal:8080}/sante"
_e18_ns=mediagenda-recette
_e18_helm_json() {
  local s
  s="$([[ -r "$_e18_kc" ]] && helm --kubeconfig "$_e18_kc" list -n "$1" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}
_e18_fichier_cluster() {
  _m18p_un_fichier_contient plateforme/distributions k3d 'recette-mediagenda' \
    || _m18p_un_fichier_contient plateforme/distributions capi 'recette-mediagenda'
}
_e18_miroirs() {
  _m18p_un_fichier_contient plateforme/distributions k3d 'mirrors' 'registry\.par1\.medisphere\.internal' \
    || _m18p_un_fichier_contient plateforme/distributions capi 'registry\.par1\.medisphere\.internal'
}

title "Cluster"
check_cmd "X3 : kubeconfig recette-mediagenda.kubeconfig en 600" _m18p_local600 "$_e18_kc"
check_cmd "le cluster recette-mediagenda répond (readyz)" _m18p_joignable "$_e18_kc"
_e18_n="$(_m18p_json "$_e18_kc" get nodes)"
check_cmd "X1 : au moins 2 nœuds Ready, kubelets en v1.36.x" _m18p_jq "$_e18_n" '
  (.items | length) >= 2 and all(.items[]; (.status.nodeInfo.kubeletVersion | test("^v1\\.36\\."))
   and any(.status.conditions[]; .type == "Ready" and .status == "True"))'
check_cmd "X1 : fichier de cluster « recette-mediagenda » versionné (k3d/ ou capi/, main)" _e18_fichier_cluster
check_cmd "X2 : configuration des images par Harbor versionnée (miroirs ou registre MédiSphère)" _e18_miroirs

title "Opérateur CloudNativePG"
_e18_cnpg_ref="$(_m18p_fichier_main plateforme/k8s releases/30-stockage.yaml.gotmpl \
  | awk '/- name: cnpg$/ {t=1} t && /version:/ {print $2; exit}')" || _e18_cnpg_ref=""
_e18_cnpg="$(_e18_helm_json cnpg-system)"
check_cmd "X4 : release cnpg deployed dans cnpg-system, chart cloudnative-pg-${_e18_cnpg_ref:-?} (version du Helmfile)" \
  _m18p_jq "$_e18_cnpg" "any(.[]; .name == \"cnpg\" and .status == \"deployed\" and .chart == \"cloudnative-pg-${_e18_cnpg_ref:-x}\")"

title "MédiAgenda"
_e18_env="$(_m18p_fichier_main mediagenda/deploiement chart.env)" || _e18_env=""
_e18_vchart="$(sed -n 's/^CHART_VERSION=//p' <<<"$_e18_env" | head -1)" || _e18_vchart=""
_e18_rel="$(_e18_helm_json "$_e18_ns")"
check_cmd "X5 : release mediagenda deployed, chart mediagenda-${_e18_vchart:-?} (CHART_VERSION de chart.env sur main)" \
  _m18p_jq "$_e18_rel" "any(.[]; .name == \"mediagenda\" and .status == \"deployed\" and .chart == \"mediagenda-${_e18_vchart:-x}\")"
_e18_dep="$(_m18p_json "$_e18_kc" -n "$_e18_ns" get deployment -l app.kubernetes.io/name=mediagenda)"
check_cmd "X6 : image medisphere/mediagenda-api:v1.1.0 de Harbor, Secret de tirage harbor-pull" _m18p_jq "$_e18_dep" '
  (.items | length) >= 1 and all(.items[]; .spec.template.spec
   | ([.containers[].image] | any(test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-api:v1\\.1\\.0(@sha256:.*)?$")))
     and ([.imagePullSecrets[]?.name] | index("harbor-pull") != null))'
check_cmd "X6 : Secret harbor-pull présent dans $_e18_ns" _m18p_k "$_e18_kc" -n "$_e18_ns" get secret harbor-pull -o name
check_cmd "X7 : déploiement terminé, tous les pods de l'API prêts" _m18p_jq "$_e18_dep" '
  (.items | length) >= 1 and all(.items[]; (.status.readyReplicas // 0) == .spec.replicas and .spec.replicas >= 1)'
_e18_pg="$(_m18p_json "$_e18_kc" -n "$_e18_ns" get clusters.postgresql.cnpg.io)"
check_cmd "X7 : Cluster CloudNativePG sain" _m18p_jq "$_e18_pg" \
  '(.items | length) >= 1 and all(.items[]; (.status.phase // "") == "Cluster in healthy state")'
_e18_nsj="$(_m18p_json "$_e18_kc" get namespace "$_e18_ns")"
check_cmd "X9 : espace étiqueté propriétaire=mediagenda, expiration ≥ aujourd'hui" _m18p_jq "$_e18_nsj" "
  .metadata.labels[\"medisphere.internal/proprietaire\"] == \"mediagenda\"
  and ((.metadata.labels[\"medisphere.internal/expiration\"] // \"\") >= \"$(date +%F)\")"

title "Service"
_e18_sante="$(curl -s --max-time "$WB_TIMEOUT" "$_e18_url" 2>/dev/null)" || _e18_sante=""
check_cmd "X8 : $_e18_url → version v1.1.0, environnement recette" _m18p_jq "${_e18_sante:-null}" \
  '.version == "v1.1.0" and .environnement == "recette"'

title "Automatisation"
if _m18p_fichier_contient plateforme/distributions Taskfile.yml 'recette:creer' 'recette:detruire'; then
  check_cmd "X10 : tâches recette:creer et recette:detruire sur main" true
else
  skip "X10 : tâches recette:creer et recette:detruire" "pas encore sur main : à fusionner après le chrono, puis relance ce contrôle"
fi
