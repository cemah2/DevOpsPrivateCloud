# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M14-E12 : Identités humaines : certificats clients et CSR
# À lancer depuis adm01. Lecture seule : le kubeconfig de Julien (~/m14/e12/julien/) est lu, et
# utilisé pour « kubectl auth whoami » et « kubectl auth can-i » (aucune écriture) ; API GitLab.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E12 — Identités humaines : certificats clients et CSR"
require_cmd jq kubectl openssl curl yq

_m14o_e12_dir="$_M14O_TRAVAIL/e12/julien"
_m14o_e12_kc="$_m14o_e12_dir/julien.petit.kubeconfig"
check_cmd "kubeconfig de Julien présent en 600 ($_m14o_e12_kc)" _m14o_local600 "$_m14o_e12_kc"
check_cmd "clé privée de Julien en 600 (julien.petit.key)" _m14o_local600 "$_m14o_e12_dir/julien.petit.key"
check_cmd "le kubeconfig produit ne contient pas la clé privée (client-key-data absent)" \
  bash -c '! grep -q "client-key-data" "$1"' _ "$_m14o_e12_kc"

_m14o_e12_pem="$(yq -r '.users[0].user."client-certificate-data" // ""' "$_m14o_e12_kc" 2>/dev/null | base64 -d 2>/dev/null || true)"
_m14o_e12_x509() { openssl x509 -noout "$@" <<<"$_m14o_e12_pem" 2>/dev/null || true; }
_m14o_e12_sujet="$(_m14o_e12_x509 -subject -nameopt multiline | tail -n +2)"
_m14o_e12_cert="$(_m14o_e12_x509 -startdate -enddate)"
check_output "certificat : CN=julien.petit" 'commonName *= *julien\.petit$' echo "$_m14o_e12_sujet"
check_cmd "certificat : un seul O, medisphere:mediagenda-devs" \
  bash -c '[[ $(grep -c organizationName <<<"$1") == 1 ]] && grep -q "organizationName *= *medisphere:mediagenda-devs$" <<<"$1"' _ "$_m14o_e12_sujet"
check_output "certificat émis par la CA du cluster (CN=kubernetes)" '^issuer=CN=kubernetes$' _m14o_e12_x509 -issuer -nameopt RFC2253
_m14o_e12_duree() {
  local d f
  d="$(sed -n 's/^notBefore=//p' <<<"$_m14o_e12_cert")"; f="$(sed -n 's/^notAfter=//p' <<<"$_m14o_e12_cert")"
  [[ -n "$d" && -n "$f" ]] || return 1
  (( $(date -d "$f" +%s) - $(date -d "$d" +%s) <= 7 * 86400 + 3600 ))
}
check_cmd "certificat valable 7 jours au plus" _m14o_e12_duree
_m14o_e12_valide() {
  local f; f="$(sed -n 's/^notAfter=//p' <<<"$_m14o_e12_cert")"
  [[ -n "$f" ]] && (( $(date -d "$f" +%s) > $(date +%s) ))
}
check_cmd "certificat non expiré (sinon : réémets-le, c'est le fonctionnement voulu)" _m14o_e12_valide

_m14o_e12_kj() { kubectl --kubeconfig "$_m14o_e12_kc" --request-timeout="${WB_TIMEOUT:-5}s" "$@" 2>/dev/null || true; }
check_cmd "l'API authentifie julien.petit dans le groupe medisphere:mediagenda-devs" \
  _m14o_json "$(_m14o_e12_kj auth whoami -o json)" \
  '.status.userInfo.username == "julien.petit" and (.status.userInfo.groups | index("medisphere:mediagenda-devs") != null)'
check_output "avec ce kubeconfig : création de Deployment permise en mediagenda-dev" '^yes$' \
  _m14o_e12_kj auth can-i create deployments.apps -n mediagenda-dev
check_output "avec ce kubeconfig : création de Deployment refusée en mediagenda-recette" '^no$' \
  _m14o_e12_kj auth can-i create deployments.apps -n mediagenda-recette

check_cmd "plateforme/k8s : outils/kubeconfig-csr.sh sur main" _m14o_fichier_main "$_M14O_P_K8S" outils/kubeconfig-csr.sh
check_cmd "plateforme/medisphere : docs/kubernetes/acces-humains.md sur main" _m14o_fichier_main "$_M14O_P_DOC" docs/kubernetes/acces-humains.md
check_output "acces-humains.md traite du retrait d'accès (révocation)" '[Rr]évoc' \
  _m14o_contenu_main "$_M14O_P_DOC" docs/kubernetes/acces-humains.md
