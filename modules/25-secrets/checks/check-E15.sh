# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M25-E15 « Tourner un secret sans redémarrage manuel ».
# Vérifie : Application reloader saine et limitée aux espaces applicatifs, Rollout mediagenda de la
# recette annoté (Secret nommé, stratégie restart, pas de nouvelle révision), Deployment medidoc
# annoté, medidoc-s3 rafraîchi toutes les 5 min avec une nouvelle version KV, prod passée aux
# identifiants dynamiques et prête, journal de la rotation.
# Lecture seule : kube (wb-checks), bao_api (métadonnées KV), curl, ~/m25/e15/.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E15 — Tourner un secret sans redémarrage manuel"
require_cmd jq kubectl curl

check_cmd "Application Argo CD reloader : Synced et Healthy" _m25o_app_ok reloader
_m25o_e15_dep="$(_m25o_k get deployments -n reloader -o json)"
check_cmd "Reloader : prise en charge d'Argo Rollouts, espaces surveillés limités (pas de surveillance globale)" \
  _m25o_json "$_m25o_e15_dep" '
  [.items[].spec.template.spec.containers[] | select(.image | test("stakater/reloader"))][0] as $c
  | $c != null
    and ([$c.args[]?, ($c.env[]? | "\(.name)=\(.value)")] | any(test("is-Argo-Rollouts=true|is-argo-rollouts=true|IS_ARGO_ROLLOUTS=true"; "i")))
    and ([$c.env[]? | select(.name == "KUBERNETES_NAMESPACE" or .name == "WATCH_NAMESPACE")] | length) + ([$c.args[]? | select(test("namespace"; "i"))] | length) > 0'
check_cmd "Reloader : pas de ClusterRole qui lit tous les Secrets du cluster" \
  _m25o_json "$(_m25o_k get clusterroles -o json)" '
  [.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "reloader" or (.metadata.name | test("reloader")))
   | .rules[]? | select((.resources // []) | index("secrets"))] | length == 0'

# --- MédiAgenda (recette) --------------------------------------------------------------------------
_m25o_e15_ro="$(_m25o_k get rollouts.argoproj.io mediagenda -n mediagenda-recette -o json)"
check_cmd "recette : Rollout mediagenda annoté pour mediagenda-db-api, stratégie restart" _m25o_json "$_m25o_e15_ro" '
  (.metadata.annotations["secret.reloader.stakater.com/reload"] // "" | split(",") | map(gsub(" "; "")) | index("mediagenda-db-api")) != null
  and .metadata.annotations["reloader.stakater.com/rollout-strategy"] == "restart"'
check_cmd "recette : le Rollout a déjà été redémarré par restartAt (sans changer de révision)" _m25o_json "$_m25o_e15_ro" '
  (.spec.restartAt // "") != "" and (.status.phase // "") == "Healthy"'
check_cmd "recette : https://mediagenda-recette.apps.par1.medisphere.internal/pret répond 200" \
  bash -c '[[ "$1" == 200 ]]' _ "$(_m25o_http https://mediagenda-recette.apps.par1.medisphere.internal/pret)"

# --- MédiDoc (recette) -----------------------------------------------------------------------------
check_cmd "medidoc-recette : Deployment medidoc annoté pour medidoc-s3" \
  _m25o_json "$(_m25o_k get deployment medidoc -n medidoc-recette -o json)" '
  (.metadata.annotations["secret.reloader.stakater.com/reload"] // "" | split(",") | map(gsub(" "; "")) | index("medidoc-s3")) != null'
_m25o_e15_es="$(_m25o_k get externalsecrets.external-secrets.io -n medidoc-recette -o json)"
check_cmd "medidoc-recette : ExternalSecret medidoc-s3 rafraîchi toutes les 5 min au plus, Ready" _m25o_json "$_m25o_e15_es" '
  any(.items[]; (.spec.target.name // .metadata.name) == "medidoc-s3"
      and ((.spec.refreshInterval // "1h") | test("^([1-5]m|[0-9]+s|[1-5]m0s)$"))
      and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) > 0)'
check_cmd "kv/medidoc/recette/s3 : au moins une rotation (version >= 2)" \
  bash -c '[[ "$1" -ge 2 ]]' _ "$(_m25o_kv_version medidoc/recette/s3)"
check_cmd "https://medidoc-recette.apps.par1.medisphere.internal/readyz répond 200" \
  bash -c '[[ "$1" == 200 ]]' _ "$(_m25o_http https://medidoc-recette.apps.par1.medisphere.internal/readyz)"

# --- Prod --------------------------------------------------------------------------------------------
check_cmd "prod : ExternalSecret mediagenda-db-api Ready" _m25o_es_pret mediagenda-prod mediagenda-db-api
check_cmd "prod : Rollout mediagenda annoté pour mediagenda-db-api" \
  _m25o_json "$(_m25o_k get rollouts.argoproj.io mediagenda -n mediagenda-prod -o json)" '
  (.metadata.annotations["secret.reloader.stakater.com/reload"] // "" | contains("mediagenda-db-api"))'
check_cmd "prod : au moins un bail mediagenda-api-prod actif" \
  bash -c '[[ "$1" -ge 1 ]]' _ "$(_m25o_baux db-mediagenda/creds/mediagenda-api-prod)"
check_cmd "prod : https://mediagenda.apps.par1.medisphere.internal/pret répond 200" \
  bash -c '[[ "$1" == 200 ]]' _ "$(_m25o_http https://mediagenda.apps.par1.medisphere.internal/pret)"

# --- Journal ---------------------------------------------------------------------------------------
check_cmd "m25/e15/choix.md : comparaison des trois façons de redémarrer, version retenue" \
  _m25o_local e15/choix.md 'reloader.*1\.4\.|1\.4\.[0-9]+'
check_cmd "m25/e15/journal.md : horodatages des rotations, sans valeur" _m25o_local e15/journal.md '[0-9]{2}:[0-9]{2}'
