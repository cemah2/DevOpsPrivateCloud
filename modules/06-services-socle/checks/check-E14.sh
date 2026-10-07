# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E14.sh — M06-E14 : Piloter PowerDNS par API et par OpenTofu
# À lancer depuis adm01. Lecture seule (GET sur l'API PowerDNS, dig, API GitLab).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E14 — Piloter PowerDNS par API et par OpenTofu"
require_cmd curl jq dig

_m06o_pvehote="${WB_PVE_HOST:-pve01}"

_m06o_zones_api() { _m06o_pdns zones | jq -e 'map(.name) | index("par1.medisphere.internal.") != null' >/dev/null; }
_m06o_sans_cle() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" \
    http://dns01.par1.medisphere.internal:8081/api/v1/servers/localhost/zones || true
}
_m06o_registre() { grep -qi 'powerdns' "${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md"; }
_m06o_module_dns() {
  gitlab_api "$_M06O_PROJET_MODULES/search?scope=blobs&search=mmianl%2Fpowerdns&ref=main" | jq -e 'length > 0' >/dev/null
}
_m06o_vmdebian_sans_dns() {
  local f code
  code="$(for f in versions.tf main.tf; do _m06o_contenu_main "$_M06O_PROJET_MODULES" "vm-debian/$f"; done)"
  # Le module a bien été lu (fournisseur proxmox présent) et ne parle pas de PowerDNS.
  grep -q 'bpg/proxmox' <<<"$code" && ! grep -qi 'powerdns' <<<"$code"
}
_m06o_ip_2063() { remote "$_m06o_pvehote" 'qm config 2063' | sed -nE 's/^ipconfig0: ip=([0-9.]+)\/.*/\1/p'; }
# Les rrsets A et PTR de m06-ipam01 portent un commentaire qui cite OpenTofu.
_m06o_commentaires_tofu() {
  _m06o_pdns "zones/par1.medisphere.internal." | jq -e '[.rrsets[]
      | select(.name == "m06-ipam01.par1.medisphere.internal." and .type == "A") | .comments[].content]
      | any(test("opentofu"; "i"))' >/dev/null \
  && _m06o_pdns "zones/10.10.in-addr.arpa." | jq -e '[.rrsets[]
      | select(.type == "PTR" and (.records[].content == "m06-ipam01.par1.medisphere.internal.")) | .comments[].content]
      | any(test("opentofu"; "i"))' >/dev/null
}

check_cmd "powerdns-api.env présent, en mode 600" _m06o_mode600 "$_M06O_CFG/powerdns-api.env"
check_cmd "l'API PowerDNS répond avec la clé (liste des zones)" _m06o_zones_api
check_output "l'API PowerDNS refuse une requête sans clé (401)" '^401$' _m06o_sans_cle
check_cmd "registre des secrets : clé d'API PowerDNS inscrite" _m06o_registre
check_cmd "tofu-modules : un module utilise le fournisseur mmianl/powerdns (sur main)" _m06o_module_dns
check_cmd "tofu-modules : vm-debian ne dépend pas de PowerDNS (module séparé)" _m06o_vmdebian_sans_dns
check_output "l'enregistrement d'essai essai-api n'existe plus (NXDOMAIN)" 'status: NXDOMAIN' \
  dig +time=3 +tries=1 @10.10.20.10 "essai-api.$_M06O_ZONE" TXT

if remote "$_m06o_pvehote" 'qm status 2063' >/dev/null 2>&1; then
  _m06o_ip="$(_m06o_ip_2063 2>/dev/null || true)"
  check_output "A de m06-ipam01 = adresse de la VM (${_m06o_ip:-?})" "^${_m06o_ip//./\\.}\$" \
    _m06o_dig "m06-ipam01.$_M06O_ZONE"
  check_output "PTR de ${_m06o_ip:-?} → m06-ipam01" '^m06-ipam01\.par1\.medisphere\.internal\.$' \
    dig +short +time=3 @10.10.20.10 -x "${_m06o_ip:-0.0.0.0}"
  check_cmd "les rrsets A et PTR de m06-ipam01 portent un commentaire OpenTofu" _m06o_commentaires_tofu
else
  skip "noms de m06-ipam01" "VM 2063 absente"
fi
