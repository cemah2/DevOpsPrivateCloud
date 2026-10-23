# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E21.sh — M28-E21 « Une équipe ne peut plus créer d'espace » : locataire medidoc prêt, propriétaire
# oidc:medidoc, de la place pour un espace, nom medidoc-… non protégé, webhooks de Capsule servis, aucune
# politique posée à la main dans capsule-system, droit de création (SubjectAccessReview) ; RB-287 ;
# panne close. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E21 — L'équipe MédiDoc crée de nouveau ses espaces"
require_cmd kubectl jq

_m28_e21_regex_libre() {
  local rx
  rx="$(kube get capsuleconfigurations.capsule.clastix.io default -o jsonpath='{.spec.protectedNamespaceRegex}' 2>/dev/null)" || return 1
  [[ -z "$rx" ]] || ! grep -Eq -- "$rx" <<<"medidoc-revue-12"
}
_m28_e21_peut_creer() {
  jq -cn '{apiVersion: "authorization.k8s.io/v1", kind: "SubjectAccessReview",
           spec: {user: "wb-verif-medidoc", groups: ["oidc:medidoc", "system:authenticated"],
                  resourceAttributes: {verb: "create", resource: "namespaces"}}}' |
    kube create -f - -o json 2>/dev/null | jq -e '.status.allowed == true' >/dev/null 2>&1
}
_m28_e21_webhook_servi() {
  kube -n capsule-system get endpointslices -l kubernetes.io/service-name=capsule-webhook-service -o json 2>/dev/null |
    jq -e '[.items[].endpoints[]? | select(.conditions.ready == true)] | length >= 1' >/dev/null 2>&1
}

if _m28p_api_repond; then
  check_cmd "locataire medidoc : prêt" _m28p_tenant medidoc 'any(.status.conditions[]?; .type == "Ready" and .status == "True")'
  check_cmd "locataire medidoc : propriétaire oidc:medidoc" _m28p_tenant medidoc '[.spec.owners[]?.name] | index("oidc:medidoc") != null'
  check_cmd "locataire medidoc : de la place pour au moins un espace de plus" _m28p_tenant medidoc \
    '(.spec.namespaceOptions.quota // 1000) > (.status.size // 0)'
  check_cmd "configuration de Capsule : un nom medidoc-revue-… n'est pas protégé" _m28_e21_regex_libre
  check_cmd "groupe oidc:medidoc autorisé à créer un espace (RBAC)" _m28_e21_peut_creer
  check_cmd "webhooks de Capsule servis (Service capsule-webhook-service avec un pod prêt)" _m28_e21_webhook_servi
  check_cmd "aucune politique Cilium posée à la main dans capsule-system" _m28p_kq \
    '[.items[] | select((.metadata.labels // {})["medisphere.internal/auteur"] != null or (.metadata.annotations // {})["argocd.argoproj.io/tracking-id"] == null)] | length == 0' \
    -n capsule-system ciliumnetworkpolicies
else
  skip "locataire, configuration, webhooks" "l'API ne répond pas au compte des checks"
fi
check_cmd "RB-287 publié (main) : messages et maillons" _m28p_doc RB-287 'RBAC' 'webhook' 'quota'
check_cmd "panne M28-E21 close (lab/bin/break 28 21 --annuler après réparation)" _m28x_aucune_panne_active E21
