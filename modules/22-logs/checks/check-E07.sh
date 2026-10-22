# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E07.sh — M22-E07 : Journal d'audit de l'API et événements Kubernetes
# À lancer depuis adm01. Lecture seule : requêtes LogQL dans les locataires audit, plateforme et
# mediagenda, DaemonSet Alloy (« kube »), RB de l'enquête sur main (GitLab).
# Prérequis : l'enquête de l'énoncé (ConfigMap m22-e07-temoin créée puis supprimée dans wb-essais).

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E07 — Journal d'audit de l'API et événements Kubernetes"
require_cmd jq kubectl curl

read -r -a _m22o_e07_cp <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"

# --- 1. Audit : un flux par nœud de contrôle, analysé ------------------------------------------------
_m22o_e07_r="$(_m22o_requete 'sum by (node) (count_over_time({job="kubernetes-audit"}[15m]))' audit 15m)"
_m22o_e07_noeuds="$(jq -r '.data.result[]?.metric.node' <<<"${_m22o_e07_r:-{\}}" 2>/dev/null | sort -u || true)"
for _m22o_e07_n in "${_m22o_e07_cp[@]}"; do
  check_cmd "audit : journal du serveur d'API de $_m22o_e07_n reçu depuis 15 min" grep -qx -- "$_m22o_e07_n" <<<"$_m22o_e07_noeuds"
done
check_cmd "audit : aucun flux venu d'un travailleur (le fichier n'existe que sur le plan de contrôle)" bash -c \
  '! grep -q "^k8s-w" <<<"$1"' _ "$_m22o_e07_noeuds"
check_cmd "audit : verb, user, code, resource en métadonnées structurées" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb '{job="kubernetes-audit"} | verb=~".+" | user=~".+" | code=~"[0-9]+" | resource=~".+"' audit 15m)"
_m22o_e07_idx="$(_m22o_etiquettes audit 15m | paste -sd, - || true)"
check_cmd "audit : seules cluster, job, node sont indexées (vu : ${_m22o_e07_idx:-rien})" bash -c \
  '[[ -n "$1" ]] && [[ -z "$(tr , "\n" <<<"$1" | grep -Ev "^(cluster|job|node)$")" ]]' _ "$_m22o_e07_idx"
check_cmd "cloisonnement : aucun événement d'audit dans le locataire plateforme" bash -c '[[ "$1" -eq 0 ]]' _ \
  "$(_m22o_nb '{job="kubernetes-audit"}' plateforme 15m)"

# --- 2. L'enquête « qui a supprimé quoi » --------------------------------------------------------------
_m22o_e07_qui="$(_m22o_requete '{job="kubernetes-audit"} | verb="delete" | resource="configmaps" | object_ns="wb-essais" | object_name="m22-e07-temoin"' audit 24h)"
check_cmd "audit : la suppression de wb-essais/configmaps/m22-e07-temoin est retrouvée (24 h)" _m22o_json "$_m22o_e07_qui" \
  '[.data.result[]?.values[]?] | length >= 1'
check_cmd "…avec l'utilisateur qui l'a faite (${WB_MOI:-ton compte})" _m22o_json "$_m22o_e07_qui" \
  '[.data.result[]? | .stream.user // empty] | any(. == $moi or ($moi == "" and . != ""))' --arg moi "${WB_MOI:-}"

# --- 3. Événements Kubernetes ------------------------------------------------------------------------------
check_cmd "événements : reçus dans le locataire plateforme (job=kubernetes-events, 2 h)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb '{job="kubernetes-events"}' plateforme 2h)"
check_cmd "événements : ceux des espaces mediagenda-* vont au locataire mediagenda (7 j)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb '{job="kubernetes-events", namespace=~"mediagenda-.+"}' mediagenda 168h)"
check_cmd "événements : pas d'étiquette instance (identifiant du composant Alloy)" bash -c \
  '! grep -qx instance <<<"$1"' _ "$(_m22o_etiquettes plateforme 2h)"
check_cmd "événements : pas de doublons (un seul pod Alloy lit les événements : clustering)" _m22o_json \
  "$(_m22o_k get daemonsets -n "$_M22O_NS" -l app.kubernetes.io/name=alloy -o json)" \
  'any(.items[0].spec.template.spec.containers[] | select(.name == "alloy") | .args[]; . == "--cluster.enabled=true")'
check_cmd "Alloy : droit de lecture des événements (et toujours pas des Secrets)" _m22o_json \
  "$(_m22o_k get clusterroles -l app.kubernetes.io/name=alloy -o json)" \
  'any(.items[].rules[]?; (.resources // []) | index("events")) and ([.items[].rules[]? | select((.resources // []) | index("secrets"))] | length == 0)'
