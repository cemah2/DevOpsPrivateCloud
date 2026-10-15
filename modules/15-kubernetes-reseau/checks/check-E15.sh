# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M15-E15 : ExternalDNS : publier les noms automatiquement
# À lancer depuis adm01. Lecture seule (kube get, dig, GitLab).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E15 — ExternalDNS : publier les noms automatiquement"
require_cmd kubectl jq dig

_m15o_d="$(_m15o_kjson deployment external-dns -n external-dns)"
_m15o_args="$(jq -r '[.spec.template.spec.containers[]? | select(.name == "external-dns") | .args[]?] | join("\n")' <<<"$_m15o_d" 2>/dev/null || true)"

# --- Déploiement -----------------------------------------------------------------------------------
check_cmd "ExternalDNS prêt dans external-dns" _m15o_jq "$_m15o_d" '(.status.readyReplicas // 0) >= 1'
check_cmd "version 0.23 (image external-dns:v0.23.x)" _m15o_jq "$_m15o_d" \
  'any(.spec.template.spec.containers[]?; .image | test("external-dns:v0\\.23\\."))'
check_cmd "fournisseur rfc2136 vers 10.10.20.10:5300, zone apps" bash -c \
  'grep -qx -- "--provider=rfc2136" <<<"$1" && grep -qx -- "--rfc2136-host=10.10.20.10" <<<"$1" && grep -qx -- "--rfc2136-port=5300" <<<"$1" && grep -qx -- "--rfc2136-zone=apps.par1.medisphere.internal" <<<"$1"' _ "$_m15o_args"
check_cmd "clé externaldns-k8s (hmac-sha256) et lecture de la zone par AXFR" bash -c \
  'grep -qx -- "--rfc2136-tsig-keyname=externaldns-k8s" <<<"$1" && grep -qx -- "--rfc2136-tsig-secret-alg=hmac-sha256" <<<"$1" && grep -qxE -- "--rfc2136-(tsig-)?axfr" <<<"$1"' _ "$_m15o_args"
check_cmd "secret TSIG absent des arguments (variable d'environnement depuis un Secret)" bash -c \
  '! grep -q -- "--rfc2136-tsig-secret=" <<<"$1"' _ "$_m15o_args"
check_cmd "variable EXTERNAL_DNS_RFC2136_TSIG_SECRET lue dans un Secret" _m15o_jq "$_m15o_d" \
  'any(.spec.template.spec.containers[]?.env[]?; .name == "EXTERNAL_DNS_RFC2136_TSIG_SECRET" and .valueFrom.secretKeyRef.name != null)'
check_cmd "politique sync, propriétaire k8s-par1, filtre de domaine apps" bash -c \
  'grep -qx -- "--policy=sync" <<<"$1" && grep -qx -- "--txt-owner-id=k8s-par1" <<<"$1" && grep -qx -- "--domain-filter=apps.par1.medisphere.internal" <<<"$1"' _ "$_m15o_args"
check_cmd "sources : routes HTTP de la Gateway API et Services" bash -c \
  'grep -qx -- "--source=gateway-httproute" <<<"$1" && grep -qx -- "--source=service" <<<"$1"' _ "$_m15o_args"
check_cmd "seules les routes de gw-par1 (passerelles) sont publiées" bash -c \
  'grep -qx -- "--gateway-name=gw-par1" <<<"$1" && grep -qx -- "--gateway-namespace=passerelles" <<<"$1"' _ "$_m15o_args"

# --- Noms publiés ------------------------------------------------------------------------------------
check_dns "$_M15O_NOM_MA résout en 10.10.41.10 (récurseurs)" "$_M15O_NOM_MA" A '^10\.10\.41\.10$'
check_output "TXT de propriété k8s-par1 à côté du nom (autoritaire)" 'external-dns/owner=k8s-par1' \
  bash -c 'for n in "a-$1" "$1"; do dig +short +norecurse -p 5300 @10.10.20.10 "$n" TXT; done' _ "$_M15O_NOM_MA"
check_output "aucun joker publié : un nom inexistant de apps est NXDOMAIN" 'status: NXDOMAIN' \
  dig +time="$WB_TIMEOUT" @10.10.20.10 "inexistant-$RANDOM.$_M15O_APPS" A
check_cmd "redirection-https porte l'étiquette d'exclusion medisphere.fr/dns=non" _m15o_jq \
  "$(_m15o_kjson httproute redirection-https -n passerelles)" '.metadata.labels["medisphere.fr/dns"] == "non"'
check_cmd "ExternalDNS exclut les objets étiquetés medisphere.fr/dns=non" bash -c \
  'grep -qxE -- "--label-filter=medisphere\\.fr/dns ?!= ?non" <<<"$1"' _ "$_m15o_args"
check_dns "essai-lb.$_M15O_APPS publié vers l'adresse du Service (10.10.41.20)" "essai-lb.$_M15O_APPS" A '^10\.10\.41\.20$'

# --- Code et documentation ----------------------------------------------------------------------------
check_cmd "composants/external-dns/values.yaml sur main de plateforme/k8s" \
  _m15o_fichier_main "$_M15O_K8S" composants/external-dns/values.yaml
check_cmd "docs/kubernetes/reseau/entree-du-cluster.md dans plateforme/medisphere" \
  _m15o_fichier_main "$_M15O_DOC" docs/kubernetes/reseau/entree-du-cluster.md
check_cmd "journal ~/m15/e15/journal.md avec les délais mesurés (au moins 10 lignes)" _m15o_journal "$_M15O_TRAVAIL/e15/journal.md" 10
