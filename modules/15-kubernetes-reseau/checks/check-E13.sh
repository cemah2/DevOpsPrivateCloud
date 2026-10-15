# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E13.sh — M15-E13 : cert-manager et l'ACME de step-ca
# À lancer depuis adm01. Lecture seule (kube get, GitLab, nft list sur gw01 et gw02).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E13 — cert-manager et l'ACME de step-ca"
require_cmd kubectl jq

_m15o_dep="$(_m15o_kjson deployments -n cert-manager)"
_m15o_ci="$(_m15o_kjson clusterissuer step-ca-acme)"
_m15o_cert="$(_m15o_kjson certificate essai-http01 -n wb-essais)"
_m15o_cms="$(_m15o_kjson configmaps -n cert-manager)"

# --- Installation -------------------------------------------------------------------------------------
_m15o_pret() { _m15o_jq "$_m15o_dep" --arg n "$1" --argjson r "$2" 'any(.items[]?; .metadata.name == $n and (.status.readyReplicas // 0) >= $r)'; }
check_cmd "contrôleur cert-manager : 2 réplicas prêts" _m15o_pret cert-manager 2
check_cmd "webhook cert-manager : 2 réplicas prêts" _m15o_pret cert-manager-webhook 2
check_cmd "cainjector prêt" _m15o_pret cert-manager-cainjector 1
check_cmd "version 1.21 du contrôleur (image cert-manager-controller:v1.21.x)" _m15o_jq "$_m15o_dep" \
  'any(.items[]?; .metadata.name == "cert-manager" and any(.spec.template.spec.containers[]?; .image | test("cert-manager-controller:v1\\.21\\.")))'
check_cmd "CRD de cert-manager installées" kube get crd certificates.cert-manager.io
check_cmd "support de la Gateway API activé dans la configuration du contrôleur" _m15o_jq "$_m15o_cms" \
  'any(.items[]?.data // {} | to_entries[]; .value | test("gatewayAPI\"?:\\s*\\{?\\s*\"?enabled\"?:\\s*true|enableGatewayAPI\"?:\\s*true"))'

# --- Émetteur -------------------------------------------------------------------------------------------
check_output "ClusterIssuer step-ca-acme : Ready" '^True$' _m15o_condition "$_m15o_ci" Ready
check_cmd "step-ca-acme : serveur ACME de ca01 et autorité fournie (caBundle)" _m15o_jq "$_m15o_ci" \
  '.spec.acme.server == "https://ca01.par1.medisphere.internal/acme/acme/directory" and ((.spec.acme.caBundle // "") | length) > 100'
check_cmd "step-ca-acme : caBundle = une racine « MédiSphère » (et elle seule)" \
  _m15o_cabundle_medisphere "$(jq -r '.spec.acme.caBundle // ""' <<<"$_m15o_ci")"
check_cmd "step-ca-acme : solveur HTTP-01 par gw-par1 (passerelles, écouteur http)" _m15o_jq "$_m15o_ci" \
  'any(.spec.acme.solvers[]?; any(.http01.gatewayHTTPRoute.parentRefs[]?; .name == "gw-par1" and .namespace == "passerelles" and .sectionName == "http"))'

# --- Certificat d'essai -----------------------------------------------------------------------------------
check_output "wb-essais/essai-http01 : Ready" '^True$' _m15o_condition "$_m15o_cert" Ready
check_cmd "essai-http01 : pour gw-par1.par1.medisphere.internal, émis par step-ca-acme (ClusterIssuer)" _m15o_jq "$_m15o_cert" \
  '(.spec.dnsNames | index("gw-par1.par1.medisphere.internal")) and .spec.issuerRef.name == "step-ca-acme" and .spec.issuerRef.kind == "ClusterIssuer"'
check_cmd "essai-http01 : valable 30 jours au plus" _m15o_jq "$_m15o_cert" \
  '((.status.notAfter | fromdateiso8601) - (.status.notBefore | fromdateiso8601)) <= 30*86400 + 3600'
check_cmd "essai-http01 : renouvelé au moins une fois (révision ≥ 2)" _m15o_jq "$_m15o_cert" '(.status.revision // 0) >= 2'

# --- Flux et code ---------------------------------------------------------------------------------------
for _m15o_g in gw01 gw02; do
  check_ssh_output "$_m15o_g : règle de transit ca01 → 10.10.41.10 TCP 80" "$_m15o_g" \
    '10\.10\.20\.11.*10\.10\.41\.10.*dport 80|10\.10\.41\.10.*10\.10\.20\.11.*dport 80' "sudo -n nft list chain inet filter forward"
done
_m15o_pf="$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_routeur/pare_feu.yml)"
check_cmd "matrice des flux (plateforme/ansible) : ca01 → GW_PAR1 tcp 80" \
  bash -c 'grep -qE "\\\$CA01.*\\\$GW_PAR1.*ports: 80|source: \\\$CA01.*10\\.10\\.41\\.10.*80" <<<"$1"' _ "$_m15o_pf"
check_cmd "values et ClusterIssuer sur main de plateforme/k8s" bash -c \
  '[[ -n "$1" && -n "$2" ]]' _ "$(_m15o_contenu_main "$_M15O_K8S" composants/cert-manager/values.yaml)" \
  "$(_m15o_contenu_main "$_M15O_K8S" composants/cert-manager/clusterissuer-step-ca-acme.yaml)"
