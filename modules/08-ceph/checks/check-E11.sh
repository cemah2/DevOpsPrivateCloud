# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E11.sh — M08-E11 : RGW : la passerelle S3 et son point d'entrée
# À lancer depuis adm01. Lecture seule (orch ls/ps, DNS, TLS, NetBox, step-ca, pare-feu en lecture).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E11 — RGW : la passerelle S3 et son point d'entrée"
require_cmd jq curl openssl dig

_m08o_nom=rgw.par1.medisphere.internal
_m08o_vip=10.10.30.200
_m08o_ls="$(_m08o_ceph orch ls --format json)"
_m08o_ps="$(_m08o_ceph orch ps --daemon_type rgw --format json)"
_m08o_export="$(_m08o_ceph orch ls ingress --export --format json)"

# --- Services ----------------------------------------------------------------------------------------
check_cmd "rgw.par1 : deux démons en service" \
  jq -e '.[] | select(.service_name == "rgw.par1") | .status.running >= 2 and .status.size >= 2' <<<"$_m08o_ls"
check_cmd "rgw.par1 : démons sur ceph02 et ceph03" \
  jq -e '[.[] | select(.service_name == "rgw.par1") | .hostname] | sort == ["ceph02","ceph03"]' <<<"$_m08o_ps"
check_cmd "ingress.rgw.par1 : deux haproxy et deux keepalived en service" \
  jq -e '.[] | select(.service_name == "ingress.rgw.par1") | .status.running >= 4' <<<"$_m08o_ls"
check_cmd "ingress.rgw.par1 : VIP 10.10.30.200/24, port 443, VRID 80" \
  jq -e '[.[] | select(.service_name == "ingress.rgw.par1" or (.service_id // "") == "rgw.par1") | .spec
          | select(.virtual_ip == "10.10.30.200/24" and .frontend_port == 443 and .first_virtual_router_id == 80)] | length == 1' <<<"$_m08o_export"

# --- Nom et adresse ---------------------------------------------------------------------------------
check_dns "$_m08o_nom → 10.10.30.200" "$_m08o_nom" A '^10\.10\.30\.200$' 10.10.20.10
check_dns "10.10.30.200 → $_m08o_nom (PTR)" "200.30.10.10.in-addr.arpa" PTR "^${_m08o_nom//./\\.}\\.$" 10.10.20.10
_m08o_nb_vip() {
  netbox_api "ipam/ip-addresses/?address=10.10.30.200" \
    | jq -e --arg n "$_m08o_nom" '.count == 1 and .results[0].dns_name == $n and (.results[0].role.value // "") == "vip"' >/dev/null
}
check_cmd "NetBox : 10.10.30.200, rôle VIP, dns_name $_m08o_nom" _m08o_nb_vip

# --- HTTPS ----------------------------------------------------------------------------------------------
check_http "https://$_m08o_nom/ répond depuis adm01 (TLS vérifié)" "https://$_m08o_nom/" 200
check_ssh "https://$_m08o_nom/ répond depuis cephcli01 (TLS vérifié)" "$_M08O_CLIENT" \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://$_m08o_nom/ | grep -qx 200"
check_ssh "https://$_m08o_nom/ répond depuis runner01 (flux ouvert, TLS vérifié)" runner01 \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://$_m08o_nom/ | grep -qx 200"
_m08o_x509="$(_m08o_cert_tls "$_m08o_nom" 443)"
check_output "certificat émis par « MédiSphère Intermediate CA »" 'issuer=.*Interm' echo "$_m08o_x509"
check_output "certificat : nom $_m08o_nom" "DNS:${_m08o_nom//./\\.}" echo "$_m08o_x509"
_m08o_duree="$(_m08o_duree_jours "$_m08o_x509")"
check_output "certificat : 30 jours au plus (durée : $_m08o_duree j)" '^([1-9]|[12][0-9]|30)$' echo "$_m08o_duree"

# --- PKI et renouvellement --------------------------------------------------------------------------
_m08o_prov="$(curl -sf --max-time "$WB_TIMEOUT" https://ca01.par1.medisphere.internal/provisioners 2>/dev/null || true)"
check_cmd "step-ca : provisioner JWK « ceph-ingress »" \
  jq -e '[.provisioners[] | select(.name == "ceph-ingress" and .type == "JWK")] | length == 1' <<<"$_m08o_prov"
if jq -e '.provisioners[] | select(.name == "ceph-ingress") | has("policy")' <<<"$_m08o_prov" >/dev/null 2>&1; then
  check_cmd "provisioner ceph-ingress : seul le nom du point d'entrée est autorisé" \
    jq -e --arg n "$_m08o_nom" '.provisioners[] | select(.name == "ceph-ingress") | .policy.x509.allow.dns == [$n]' <<<"$_m08o_prov"
else
  skip "politique du provisioner ceph-ingress" "non publiée par /provisioners : vérifie le refus d'un autre nom (journal)"
fi
check_cmd "adm01 : ceph-cert-ingress.timer actif" systemctl is-active --quiet ceph-cert-ingress.timer
check_cmd "adm01 : mot de passe du provisioner en 600" _m08o_local600 "$_M08O_CFG/step-ceph-ingress.pass"
check_cmd "adm01 : dossier du certificat en 700" \
  bash -c '[[ "$(stat -c %a "$1" 2>/dev/null)" == 700 ]]' _ "$_M08O_CFG/ceph-ingress"
check_cmd "registre des secrets : provisioner ceph-ingress inscrit" _m08o_registre 'ceph-ingress'
_m08o_sans_cle() {
  # Aucune clé privée dans specs/ingress.yaml, ni dans la copie de travail ni sur main.
  ! grep -qs 'PRIVATE KEY' "${WB_SRC:-$HOME/src}/ceph/specs/ingress.yaml" \
    && ! _m08o_contenu_main "$_M08O_PROJET_CEPH" specs/ingress.yaml | grep -q 'PRIVATE KEY'
}
check_cmd "aucune clé privée dans specs/ingress.yaml (copie de travail, main)" _m08o_sans_cle

# --- Flux ---------------------------------------------------------------------------------------------
for _m08o_gw in gw01 gw02; do
  check_ssh "$_m08o_gw : transit runner01 → 10.10.30.200 TCP 443 autorisé" "$_m08o_gw" \
    'sudo -n nft list chain inet filter forward | grep "10.10.20.15" | grep "10.10.30.200" | grep -E "dport 443" | grep -q accept'
done
