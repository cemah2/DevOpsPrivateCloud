# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E40.sh — M15-E40 « Panne : le certificat n'est jamais délivré » : émetteur prêt et conforme
# (serveur ACME, CA MédiSphère, solveur RFC 2136 vers dns01 avec la clé certmanager-k8s, sélecteur
# de la zone apps), tous les certificats du workbook délivrés. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E40 — Les certificats sont délivrés"
require_cmd kubectl jq openssl

check_cmd "ClusterIssuer step-ca-acme prêt (Ready=True)" \
  _m15x_jq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' clusterissuer step-ca-acme
check_cmd "serveur ACME : ca01" \
  _m15x_jq '.spec.acme.server == "https://ca01.par1.medisphere.internal/acme/acme/directory"' clusterissuer step-ca-acme
check_cmd "solveur RFC 2136 : autoritaire de dns01 (10.10.20.10:5300) et clé certmanager-k8s" \
  _m15x_jq '[.spec.acme.solvers[] | .dns01.rfc2136? | select(. != null) | select((.nameserver | test("^10\\.10\\.20\\.10:5300$")) and (.tsigKeyName | test("^certmanager-k8s\\.?$")))] | length > 0' \
  clusterissuer step-ca-acme
check_cmd "le solveur DNS-01 couvre la zone $_m15x_zone" \
  _m15x_jq "[.spec.acme.solvers[] | select(.dns01.rfc2136 != null) | .selector // {} | ((.dnsZones // []) | index(\"$_m15x_zone\") != null) or ((.dnsNames // []) | index(\"*.$_m15x_zone\") != null) or (. == {})] | any" \
  clusterissuer step-ca-acme
_m15_e40_bundle="$(kube get clusterissuer step-ca-acme -o jsonpath='{.spec.acme.caBundle}' 2>/dev/null | base64 -d 2>/dev/null)" || true
if [[ -r "$_m15x_ca" ]]; then
  _m15_e40_emp="$(openssl x509 -in "$_m15x_ca" -noout -fingerprint -sha256 2>/dev/null)" || true
  check_cmd "caBundle de l'émetteur : contient la racine MédiSphère de adm01" bash -c '
    d="$(mktemp -d)" || exit 1
    printf "%s\n" "$1" | awk -v d="$d" "/-----BEGIN CERTIFICATE-----/ {n++} n {print > (d \"/c\" n \".pem\")}"
    r=1
    for c in "$d"/c*.pem; do
      [ -s "$c" ] || continue
      [ "$(openssl x509 -in "$c" -noout -fingerprint -sha256 2>/dev/null)" = "$2" ] && r=0
    done
    rm -rf "$d"
    exit $r' _ "$_m15_e40_bundle" "$_m15_e40_emp"
else
  skip "caBundle comparé à la racine MédiSphère" "$_m15x_ca absent de ce poste"
fi
check_cmd "certificat passerelles/apps-joker délivré" \
  _m15x_jq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' -n "$_m15x_gw_ns" certificate apps-joker
check_cmd "tous les certificats de passerelles, wb-* et mediagenda-* sont délivrés" \
  _m15x_jq '[.items[] | select(.metadata.namespace | test("^(passerelles|wb-.*|mediagenda-.*)$"))
    | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)] | length == 0' certificates -A
check_cmd "panne M15-E40 close (lab/bin/break 15 40 --annuler après réparation)" _m15x_aucune_panne_active E40
