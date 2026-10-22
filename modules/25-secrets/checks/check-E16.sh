# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M25-E16 « PKI de services : MédiSphère Services CA et cert-manager ».
# Vérifie : moteur pki-services/, CA publiée vérifiable contre la racine MédiSphère, nom et durée,
# CRL publiée et à jour, rôle services-k8s au plus juste, procès-verbal de cérémonie, ClusterIssuer
# openbao-services Ready, Certificate mTLS de la recette Ready et courts, relais TLS en place,
# politiques réseau sur 8443, essais du TLS mutuel notés.
# Lecture seule : points publics de la PKI (ca/pem, crl/pem), bao_api (rôle), kube, gitlab_api, ~/m25/e16/.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E16 — PKI de services : « MédiSphère Services CA » et cert-manager"
require_cmd jq kubectl curl openssl

_m25o_e16_racine="${WB_RACINE_MEDISPHERE:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_m25o_e16_tmp="$(mktemp -d)"
trap 'rm -rf "$_m25o_e16_tmp"' EXIT
curl -s --max-time "$WB_TIMEOUT" "$_M25O_BAO/v1/pki-services/ca/pem" -o "$_m25o_e16_tmp/ca.pem" 2>/dev/null || true
curl -s --max-time "$WB_TIMEOUT" "$_M25O_BAO/v1/pki-services/crl/pem" -o "$_m25o_e16_tmp/crl.pem" 2>/dev/null || true

check_cmd "moteur pki-services/ monté, de type pki" _m25o_moteur_type pki-services pki
check_cmd "CA publiée (pki-services/ca/pem) vérifiable contre la racine MédiSphère" \
  openssl verify -CAfile "$_m25o_e16_racine" "$_m25o_e16_tmp/ca.pem"
check_output "CA publiée : CN « MédiSphère Services CA »" 'CN ?= ?M.{1,8}diSph.{1,8}re Services CA' \
  openssl x509 -in "$_m25o_e16_tmp/ca.pem" -noout -subject -nameopt utf8,sep_comma_plus_space
_m25o_e16_duree() {
  local debut fin
  debut="$(date -d "$(openssl x509 -in "$_m25o_e16_tmp/ca.pem" -noout -startdate | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -in "$_m25o_e16_tmp/ca.pem" -noout -enddate | cut -d= -f2)" +%s)" || return 1
  # trois ans à quelques jours près (cérémonie : DUREE_INTERMEDIAIRE=26280h)
  ((fin - debut > 1085 * 86400 && fin - debut < 1100 * 86400))
}
check_cmd "CA publiée : valable trois ans (26280 h), pas cinq" _m25o_e16_duree
check_output "CA publiée : autorité de chemin nul (pathlen:0)" 'CA:TRUE, pathlen:0' \
  openssl x509 -in "$_m25o_e16_tmp/ca.pem" -noout -ext basicConstraints
_m25o_e16_crl() {
  local prochaine
  openssl crl -in "$_m25o_e16_tmp/crl.pem" -noout -CAfile "$_m25o_e16_tmp/ca.pem" 2>&1 | grep -q 'verify OK' || return 1
  prochaine="$(openssl crl -in "$_m25o_e16_tmp/crl.pem" -noout -nextupdate | cut -d= -f2)"
  (($(date -d "$prochaine" +%s) > $(date +%s)))
}
check_cmd "CRL publiée (pki-services/crl/pem), signée par la Services CA et non périmée" _m25o_e16_crl

check_cmd "rôle services-k8s : svc et svc.cluster.local seulement, sans IP ni localhost, 72 h au plus, client et serveur" \
  _m25o_json "$(_m25o_bao pki-services/roles/services-k8s)" '
  (.data.allowed_domains | sort) == ["svc", "svc.cluster.local"]
  and .data.allow_subdomains == true and .data.allow_ip_sans == false and .data.allow_localhost == false
  and .data.allow_any_name == false and .data.max_ttl > 0 and .data.max_ttl <= 259200
  and .data.server_flag == true and .data.client_flag == true'
check_cmd "politique cert-manager-services : signer par services-k8s, rien d'autre sur pki-services" \
  bash -c 'grep -q "pki-services/sign/services-k8s" <<<"$1" && ! grep -Eq "pki-services/(issue|root|intermediate|config|revoke|\*)" <<<"$1"' _ \
  "$(_m25o_politique cert-manager-services)"
check_cmd "rôle k8s-par1 cert-manager-services : compte openbao-emetteur de cert-manager, audience exigée" \
  _m25o_json "$(_m25o_bao auth/k8s-par1/role/cert-manager-services)" '
  .data.bound_service_account_names == ["openbao-emetteur"] and .data.bound_service_account_namespaces == ["cert-manager"]
  and .data.audience == "openbao.medisphere.internal"'

check_cmd "procès-verbal de la cérémonie « MédiSphère Services CA » dans ceremonie-ca.md (main)" \
  _m25o_doc_contient docs/securite/identite/ceremonie-ca.md 'Services CA'
check_cmd "CSR et certificat de la Services CA versionnés dans pki/ de plateforme/ansible" \
  _m25o_fichier "$_M25O_P_ANSIBLE" pki/openbao-services.crt

# --- cert-manager ----------------------------------------------------------------------------------
check_cmd "ClusterIssuer openbao-services : Ready, chemin pki-services/sign/services-k8s, méthode k8s-par1" \
  _m25o_json "$(_m25o_k get clusterissuers.cert-manager.io openbao-services -o json)" '
  ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) > 0
  and .spec.vault.path == "pki-services/sign/services-k8s"
  and .spec.vault.auth.kubernetes.mountPath == "/v1/auth/k8s-par1"'
# _m25o_e16_cert ESPACE NOM — Certificate Ready, émis par openbao-services, 72 h au plus.
_m25o_e16_cert() {
  _m25o_json "$(_m25o_k get certificates.cert-manager.io "$2" -n "$1" -o json)" '
    ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) > 0
    and .spec.issuerRef.name == "openbao-services" and .spec.issuerRef.kind == "ClusterIssuer"
    and ((.status.notAfter | fromdateiso8601) - (.status.notBefore | fromdateiso8601)) <= 259200
    and ((.spec.usages // []) | index("client auth")) != null'
}
check_cmd "medidoc-recette : Certificate medidoc-mtls Ready, émis par openbao-services, 72 h au plus" \
  _m25o_e16_cert medidoc-recette medidoc-mtls
check_cmd "mediagenda-recette : Certificate mediagenda-mtls Ready, émis par openbao-services, 72 h au plus" \
  _m25o_e16_cert mediagenda-recette mediagenda-mtls

# --- Relais et réseau ------------------------------------------------------------------------------
check_cmd "medidoc-recette : relais TLS (ghostunnel server) dans les pods de medidoc, port 8443 au Service" \
  _m25o_json "$(_m25o_k get deployment medidoc -n medidoc-recette -o json)" '
  [.spec.template.spec.initContainers[]?, .spec.template.spec.containers[]?
   | select((.image | test("ghostunnel")) and ((.args // []) | index("server")) != null)] | length == 1'
check_cmd "medidoc-recette : le relais exige un nom de client précis (pas --allow-all)" \
  _m25o_json "$(_m25o_k get deployment medidoc -n medidoc-recette -o json)" '
  [.spec.template.spec.initContainers[]?, .spec.template.spec.containers[]? | select(.image | test("ghostunnel")) | .args[]]
  | (any(test("^--allow-(dns|uri|cn)")) and (any(. == "--allow-all") | not) and (any(. == "--disable-authentication") | not))'
check_cmd "mediagenda-recette : MédiAgenda appelle MédiDoc par le relais local" \
  _m25o_json "$(_m25o_k get deployment mediagenda -n mediagenda-recette -o json)" '
  [.spec.template.spec.initContainers[]?, .spec.template.spec.containers[]? | select(.image | test("ghostunnel")) | .args[]]
  | index("client") != null'
check_cmd "medidoc-recette : MédiAgenda n'entre plus que sur 8443 (politique medidoc-entree-mediagenda)" \
  _m25o_json "$(_m25o_k get ciliumnetworkpolicies.cilium.io medidoc-entree-mediagenda -n medidoc-recette -o json)" '
  [.spec.ingress[]?.toPorts[]?.ports[]?.port] == ["8443"]'
check_cmd "m25/e16/essais-mtls.md : appel de bout en bout et refus sans certificat notés" \
  _m25o_local e16/essais-mtls.md 'certificate|handshake|refus'
check_cmd "docs/securite/secrets/pki-services.md sur main" _m25o_fichier "$_M25O_P_DOC" "$_M25O_DOC_SECRETS/pki-services.md"
