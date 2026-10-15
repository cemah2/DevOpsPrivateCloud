# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E23.sh — M15-E23 : Le réseau du cluster décrit par le code
# À lancer depuis adm01. Lecture seule : contenu de plateforme/k8s sur main (GitLab), dernier
# pipeline de main, comparaison de quelques champs du cluster avec le dépôt, journal de dérive.
# (La tâche de dérive elle-même demande des droits d'écriture en dry-run : le check lit sa sortie
# consignée, il ne la lance pas avec le compte en lecture.)

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E23 — Le réseau du cluster décrit par le code"
require_cmd kubectl jq yq

_m15o_arbre="$(_m15o_arbre_main "$_M15O_K8S" "")"
_m15o_a() { grep -qE -- "$1" <<<"$_m15o_arbre"; }

# --- Contenu du dépôt ---------------------------------------------------------------------------------
check_cmd "values de Cilium (composants/cilium/values.yaml)" _m15o_a '^composants/cilium/values\.yaml$'
check_cmd "CRD de la Gateway API versionnées (composants/gateway-api/)" _m15o_a '^composants/gateway-api/'
check_cmd "pool LB IPAM et objets BGP" bash -c 'grep -q "^composants/cilium/lb-ipam/" <<<"$1" && grep -q "^composants/cilium/bgp/" <<<"$1"' _ "$_m15o_arbre"
check_cmd "Gateway et routes de plateforme (composants/passerelles/)" _m15o_a '^composants/passerelles/'
check_cmd "cert-manager : values et émetteur" bash -c 'grep -q "^composants/cert-manager/values\.yaml$" <<<"$1" && grep -q "^composants/cert-manager/clusterissuer" <<<"$1"' _ "$_m15o_arbre"
check_cmd "ExternalDNS : values" _m15o_a '^composants/external-dns/values\.yaml$'
check_cmd "CoreDNS géré (composants/coredns/)" _m15o_a '^composants/coredns/'
check_cmd "outil des secrets TSIG (outils/secret-tsig.sh)" _m15o_a '^outils/secret-tsig\.sh$'
check_cmd "aucun Secret ni clé privée dans le dépôt" _m15o_depot_sans_secret

# --- Versions épinglées -------------------------------------------------------------------------------
_m15o_task="$(grep -E '^Taskfile[^/]*\.ya?ml$' <<<"$_m15o_arbre" | while read -r f; do _m15o_contenu_main "$_M15O_K8S" "$f"; done || true)"
check_cmd "Taskfile : une tâche d'installation et une tâche de dérive du réseau" \
  bash -c 'grep -qiE "^ *(reseau:)?(installer|install|appliquer)[a-z:-]*:" <<<"$1" && grep -qiE "^ *(reseau:)?(derive|dérive|drift)[a-z:-]*:" <<<"$1"' _ "$_m15o_task"
check_cmd "aucune version flottante dans composants/ et le Taskfile (latest, image sans étiquette)" \
  bash -c '! grep -qE "(:latest\\b|--version +latest)" <<<"$1"' _ "$_m15o_task$(_m15o_contenu_main "$_M15O_K8S" composants/cilium/values.yaml)"

# --- CI -------------------------------------------------------------------------------------------------
_m15o_ci="$(_m15o_contenu_main "$_M15O_K8S" .gitlab-ci.yml)"
check_cmd "CI : validation des manifestes (kubeconform ou équivalent)" bash -c 'grep -qiE "kubeconform|kubeval|dry-run=server" <<<"$1"' _ "$_m15o_ci"
# (fonction locale : « gitlab_api » est une fonction de check-lib.sh, invisible dans un « bash -c »)
_m15o_dernier_pipeline() { gitlab_api "$_M15O_K8S/pipelines?ref=main&per_page=1" | jq -r '.[0].status'; }
check_output "CI : dernier pipeline de main réussi" '^success$' _m15o_dernier_pipeline

# --- Cluster conforme au dépôt (échantillon) -------------------------------------------------------------
_m15o_pool_git="$(_m15o_contenu_main "$_M15O_K8S" composants/cilium/lb-ipam/lb-par1.yaml | yq -o json '.spec.blocks' 2>/dev/null | jq -c . 2>/dev/null || true)"
_m15o_pool_k8s="$(_m15o_kjson ciliumloadbalancerippool lb-par1 | jq -c '.spec.blocks' 2>/dev/null || true)"
check_cmd "pool lb-par1 du cluster identique au dépôt" bash -c '[[ -n "$1" && "$1" != null && "$1" == "$2" ]]' _ "$_m15o_pool_git" "$_m15o_pool_k8s"
_m15o_gw_git="$(_m15o_contenu_main "$_M15O_K8S" composants/passerelles/gw-par1.yaml | yq -o json '.spec.listeners | map(.name) | sort' 2>/dev/null | jq -c . 2>/dev/null || true)"
_m15o_gw_k8s="$(_m15o_kjson gateway gw-par1 -n passerelles | jq -c '.spec.listeners | map(.name) | sort' 2>/dev/null || true)"
check_cmd "écouteurs de gw-par1 identiques au dépôt" bash -c '[[ -n "$1" && "$1" != null && "$1" == "$2" ]]' _ "$_m15o_gw_git" "$_m15o_gw_k8s"

# --- Preuves ------------------------------------------------------------------------------------------
check_cmd "docs/kubernetes/reseau/reconstruction.md dans plateforme/medisphere" \
  _m15o_fichier_main "$_M15O_DOC" docs/kubernetes/reseau/reconstruction.md
check_cmd "m15/e23/ : sortie de la tâche de dérive sans écart consignée" \
  bash -c 'grep -qsiE "aucune d[ée]rive|no drift" "$1"/*' _ "$_M15O_TRAVAIL/e23"
