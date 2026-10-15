# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M15-E05 : Cilium et Hubble : observer les flux
# À lancer depuis adm01. Lecture seule : relay Hubble et ConfigMap cilium-config (wb-checks), valeurs de
# Cilium et fiche sur main (API GitLab en GET), objets d'essai de wb-essais.

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E05 — Cilium et Hubble : observer les flux"
require_cmd kubectl jq yq curl

# --- Hubble en service -----------------------------------------------------------------------------------
check_output "Hubble activé dans les agents (enable-hubble)" '^true$' _m15d_cilium_cfg enable-hubble
_m15d_e05_relay="$(_m15d_get -n kube-system deployment hubble-relay)"
check_cmd "hubble-relay : tous ses réplicas prêts" _m15d_json "$_m15d_e05_relay" \
  '(.status.readyReplicas // 0) >= 1 and (.status.readyReplicas // 0) == (.spec.replicas // 1)'
_m15d_e05_ds="$(_m15d_get -n kube-system daemonset cilium)"
check_cmd "agents Cilium prêts sur tous les nœuds (${#_M15D_NOEUDS[@]})" _m15d_json "$_m15d_e05_ds" \
  '.status.numberReady == .status.desiredNumberScheduled and .status.numberReady == $n' \
  --argjson n "${#_M15D_NOEUDS[@]}"

# --- Rédaction des champs sensibles (SEC-1605), telle que les agents la lisent ------------------------------
check_output "rédaction Hubble activée (hubble-redact-enabled)" '^true$' _m15d_cilium_cfg hubble-redact-enabled
check_output "paramètres d'URL rédigés (hubble-redact-http-urlquery)" '^true$' _m15d_cilium_cfg hubble-redact-http-urlquery
check_output "informations d'utilisateur rédigées (hubble-redact-http-userinfo)" '^true$' _m15d_cilium_cfg hubble-redact-http-userinfo
_m15d_e05_deny="$(_m15d_cilium_cfg hubble-redact-http-headers-deny | tr '[:upper:]' '[:lower:]')"
check_cmd "en-têtes Authorization et Cookie rédigés (hubble-redact-http-headers-deny)" \
  bash -c 'grep -qw "authorization" <<<"$1" && grep -qw "cookie" <<<"$1"' _ "$_m15d_e05_deny"
check_cmd "pas de liste d'en-têtes « autorisés » en même temps (allow et deny sont exclusifs)" \
  bash -c '[[ -n "$1" && -z "$2" ]]' _ "$_m15d_e05_deny" "$(_m15d_cilium_cfg hubble-redact-http-headers-allow | tr -d '[:space:]')"

check_cmd "chaque agent Cilium a redémarré après la dernière modification de cilium-config (réglages appliqués)" \
  _m15d_agents_a_jour

# --- Les réglages sont dans le code -------------------------------------------------------------------------
_m15d_e05_values="$(_m15d_contenu_main "$_M15D_PROJET_K8S" composants/cilium/values.yaml)"
check_cmd "composants/cilium/values.yaml sur main de plateforme/k8s" test -n "$_m15d_e05_values"
_m15d_e05_yq() {
  yq -e '.hubble.redact.enabled == true and .hubble.redact.http.urlQuery == true
    and ((.hubble.redact.http.headers.deny // []) | map(downcase) | contains(["authorization", "cookie"]))' \
    <<<"$_m15d_e05_values" >/dev/null 2>&1
}
check_cmd "les values du dépôt portent la même rédaction (hubble.redact)" _m15d_e05_yq

# --- Ménage des essais ----------------------------------------------------------------------------------------
check_cmd "Service d'essai « vide » retiré" _m15d_absent -n "$_M15D_NS" service vide
check_cmd "politique d'essai visibilite-l7-echo retirée" _m15d_absent -n "$_M15D_NS" ciliumnetworkpolicy visibilite-l7-echo

# --- La fiche ------------------------------------------------------------------------------------------------
_m15d_e05_doc="$(_m15d_contenu_main "$_M15D_PROJET_DOC" docs/kubernetes/reseau/hubble.md)"
check_cmd "docs/kubernetes/reseau/hubble.md sur main" test -n "$_m15d_e05_doc"
check_cmd "la fiche donne des filtres (verdict, espace, pod) et parle de la rédaction" \
  bash -c 'grep -q -- "--verdict" <<<"$1" && grep -qE -- "(-n|--namespace) " <<<"$1" && grep -qE -- "--(from-|to-)?pod" <<<"$1" && grep -qiE "rédaction|redact" <<<"$1"' \
  _ "$_m15d_e05_doc"
