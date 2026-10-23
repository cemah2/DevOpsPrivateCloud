# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E15.sh — M28-E15 « Isolation des locataires » : PSA restricted et refus réseau par défaut dans
# tous les espaces des locataires, cloison Cilium par étiquette de locataire, politiques
# locataires-placement et locataires-pod-security, Services exposés refusés, préfixe imposé, essais
# nettoyés, rapport. Lecture seule.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

title "M28-E15 — Isolation des locataires"
require_cmd kubectl jq curl

_m28_e15_espaces_psa() {
  kube get namespaces -l capsule.clastix.io/tenant -o json 2>/dev/null |
    jq -e '(.items | length) > 0 and all(.items[]; .metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted")' >/dev/null 2>&1
}
_m28_e15_refus_defaut() {
  local ns
  ns="$(kube get namespaces -l capsule.clastix.io/tenant -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$ns" ]] || return 1
  local n
  for n in $ns; do
    kube -n "$n" get networkpolicy refus-par-defaut >/dev/null 2>&1 || return 1
  done
}
_m28_e15_cloison() {
  kube get ciliumclusterwidenetworkpolicies -o json 2>/dev/null | jq -e --arg t "$1" '
    [.items[] | select(.spec.endpointSelector.matchLabels["io.cilium.k8s.namespace.labels.capsule.clastix.io/tenant"] == $t)
              | select((.spec.ingressDeny // []) | length > 0)] | length >= 1' >/dev/null 2>&1
}

_m28_e15_prefixe() {
  _m28p_tenant "$1" '.spec.forceTenantPrefix == true' ||
    _m28p_kq '.spec.forceTenantPrefix == true' capsuleconfigurations.capsule.clastix.io default
}
_m28_e15_essai_absent() { ! kube get namespace medidoc-essai-isolation >/dev/null 2>&1; }

if _m28p_api_repond; then
  check_cmd "tout espace de locataire porte pod-security.kubernetes.io/enforce=restricted" _m28_e15_espaces_psa
  check_cmd "tout espace de locataire a la NetworkPolicy refus-par-defaut" _m28_e15_refus_defaut
  for _m28_e15_t in mediagenda medinotif medidoc; do
    check_cmd "locataire $_m28_e15_t : cloison Cilium sur l'étiquette capsule.clastix.io/tenant" _m28_e15_cloison "$_m28_e15_t"
    check_cmd "locataire $_m28_e15_t : Services LoadBalancer, NodePort, ExternalName refusés" _m28p_tenant "$_m28_e15_t" \
      '[.spec.rules[]?.enforce | select(.action == "deny") | .services.types[]?] as $t
       | (($t | index("LoadBalancer")) != null and ($t | index("NodePort")) != null and ($t | index("ExternalName")) != null)'
    check_cmd "locataire $_m28_e15_t : préfixe imposé" _m28_e15_prefixe "$_m28_e15_t"
  done
  for _m28_e15_p in locataires-placement locataires-pod-security; do
    check_cmd "ValidatingPolicy Kyverno $_m28_e15_p chargée (Deny)" _m28p_kq \
      '(.spec.validationActions // []) | index("Deny") != null' validatingpolicies.policies.kyverno.io "$_m28_e15_p"
  done
  check_cmd "GeneratingPolicy networkpolicy-par-defaut : déclenchée aussi par l'étiquette de Capsule" _m28p_kq \
    '[.spec.matchConditions[]?.expression] | any(test("capsule.clastix.io/tenant"))' generatingpolicies.policies.kyverno.io networkpolicy-par-defaut
  check_cmd "espace d'essai medidoc-essai-isolation supprimé" _m28_e15_essai_absent
else
  skip "espaces, locataires, politiques" "l'API ne répond pas au compte des checks"
fi

_m28_e15_compte() {
  local r
  r="$(ipa_ldap '(uid=essai-medidoc)' nsAccountLock 2>/dev/null)" || return 2
  [[ -z "$r" ]] || grep -qi 'nsAccountLock: TRUE' <<<"$r"
}
if [[ -r "${WB_IPA_CHECKS_FILE:-$HOME/.config/workbook/ipa-checks.env}" ]]; then
  check_cmd "compte d'essai essai-medidoc désactivé ou absent" _m28_e15_compte
else
  skip "compte d'essai essai-medidoc désactivé" "identifiants LDAP des checks absents"
fi
check_cmd "essais-isolation.md (main) : essais, trous et corrections" \
  _m28p_doc essais-isolation 'cluster-admin' 'LoadBalancer|ExternalName' 'nodeName' 'Secret'
