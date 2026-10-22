# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M20-E37 « Panne : Argo CD ne lit plus le dépôt » : aucune Application en erreur de
# comparaison, racine MédiSphère dans argocd-tls-certs-cm, aucune politique qui refuse git01 au
# repo-server, labo pointe sur la forge, dépôts déclarés joignables (API d'Argo CD), RB-200 et
# journal, panne close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E37 — Argo CD lit à nouveau Git"
require_cmd jq kubectl curl openssl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "aucune Application en erreur de comparaison ou de spécification" _m20x_apps_sans 'ComparisonError|InvalidSpecError'
  for _m20_e37_a in racine "$_m20x_app_dev" "$_m20x_app_labo"; do
    check_cmd "$_m20_e37_a : Synced, Healthy" _m20x_app_saine "$_m20_e37_a"
  done
  check_cmd "$_m20x_app_labo : source sur la forge git01.par1.medisphere.internal" \
    _m20x_app_jq "$_m20x_app_labo" '[(.spec.source.repoURL // empty), (.spec.sources[]?.repoURL // empty)] | length > 0 and all(test("^https://git01\\.par1\\.medisphere\\.internal/"))'
fi
_m20_e37_ca_forge() {
  local pem
  pem="$(_m20x_cm "$_m20x_ns" argocd-tls-certs-cm | jq -r '.data["git01.par1.medisphere.internal"] // empty')"
  [[ -n "$pem" ]] || return 1
  # Le certificat présenté par la forge doit se valider avec ce que contient l'entrée, et rien d'autre.
  openssl s_client -connect git01.par1.medisphere.internal:443 -servername git01.par1.medisphere.internal \
    -CAfile <(printf '%s\n' "$pem") -verify_return_error </dev/null 2>/dev/null | grep -q 'Verify return code: 0 (ok)'
}
check_cmd "argocd-tls-certs-cm : l'entrée git01.par1.medisphere.internal valide le certificat de la forge" _m20_e37_ca_forge
_m20_e37_aucun_refus_forge() {
  kube -n "$_m20x_ns" get ciliumnetworkpolicies.cilium.io -o json 2>/dev/null | jq -e '
    [.items[] | ((.spec.egressDeny // []) + [.specs[]?.egressDeny[]?])[]
     | select(any((.toCIDR // [])[], (.toCIDRSet // [])[].cidr; test("^10\\.10\\.20\\.(12/32|0/24)$|^10\\.10\\.0\\.0/16$|^0\\.0\\.0\\.0/0$")))] | length == 0' >/dev/null 2>&1
}
check_cmd "espace argocd : aucune CiliumNetworkPolicy de refus vers git01 (10.10.20.12)" _m20_e37_aucun_refus_forge
_m20_e37_depots() { _m20x_argocd_api repositories | jq -e '[.items[]? | select((.connectionState.status // "Successful") != "Successful")] | length == 0' >/dev/null 2>&1; }
if _m20x_argocd_api repositories >/dev/null 2>&1; then
  check_cmd "API d'Argo CD : tous les dépôts déclarés en état de connexion « Successful »" _m20_e37_depots
else
  skip "état de connexion des dépôts" "API d'Argo CD illisible avec ~/.config/workbook/argocd-checks.token (M20-E03)"
fi
check_cmd "RB-200 : section sur le dépôt illisible" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(dépôt|repo)'
check_cmd "journal de diagnostic de INC-4737 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4737'
check_cmd "panne M20-E37 close (lab/bin/break 20 37 --annuler après réparation)" _m20x_aucune_panne_active E37
