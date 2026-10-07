# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E13.sh — M06-E13 : Allouer les adresses depuis NetBox avec OpenTofu
# À lancer depuis adm01. Lecture seule (API NetBox, API GitLab, qm config sur pve01).
# VM m06-ipam01 (2063) présente : cohérence NetBox/Proxmox. Détruite : aucune adresse orpheline.

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E13 — Allouer les adresses depuis NetBox avec OpenTofu"
require_cmd curl jq

_m06o_checks="${WB_NETBOX_TOKEN_FILE:-$_M06O_CFG/netbox-checks.token}"
_m06o_pvehote="${WB_PVE_HOST:-pve01}"

_m06o_statut_ip() { _m06o_nb "$_m06o_checks" "ipam/ip-addresses/?address=$1" | jq -r '.results[0].status.value // empty'; }
_m06o_module_netbox() {
  local f
  for f in versions.tf main.tf netbox.tf; do _m06o_contenu_main "$_M06O_PROJET_MODULES" "vm-debian/$f" v2.0.0; done \
    | grep -q 'e-breuninger/netbox'
}
_m06o_env_v2() { _m06o_contenu_main "$_M06O_PROJET_INFRA" envs/lab-m06/main.tf | grep -Eq 'vm-debian\?ref=v2\.[0-9]+\.[0-9]+'; }
_m06o_sans_jeton() {
  local code
  code="$(_m06o_contenu_main "$_M06O_PROJET_INFRA" envs/lab-m06/providers.tf
          _m06o_contenu_main "$_M06O_PROJET_INFRA" envs/lab-m06/main.tf)"
  # Contenu lu (la forge a répondu) ET aucun jeton : un dépôt illisible ne doit pas passer.
  grep -q 'netbox' <<<"$code" && ! grep -q 'nbt_' <<<"$code"
}
_m06o_ipconfig() { remote "$_m06o_pvehote" 'qm config 2063' | sed -n 's/^ipconfig0: //p'; }

# --- Adresses futures réservées ----------------------------------------------------------------------
for _m06o_ip in 10.10.20.21 10.10.20.22 10.10.20.23 10.10.20.30; do
  check_output "NetBox : $_m06o_ip réservée (PLAN §4.5, hôte futur)" '^reserved$' _m06o_statut_ip "$_m06o_ip"
done

# --- Module et environnement ----------------------------------------------------------------------------
check_cmd "tofu-modules : étiquette v2.x.y publiée" _m06o_etiquette "$_M06O_PROJET_MODULES" '^v2\.[0-9]+\.[0-9]+$'
check_cmd "tofu-modules (v2.0.0) : vm-debian utilise le fournisseur e-breuninger/netbox" _m06o_module_netbox
check_cmd "infra : envs/lab-m06 consomme vm-debian par une étiquette v2" _m06o_env_v2
check_cmd "netbox-tofu.env présent, en mode 600" _m06o_mode600 "$_M06O_CFG/netbox-tofu.env"
check_cmd "aucun jeton NetBox dans le code de envs/lab-m06" _m06o_sans_jeton

# --- La VM d'essai ------------------------------------------------------------------------------------------
_m06o_vm="$(_m06o_nb "$_m06o_checks" 'virtualization/virtual-machines/?name=m06-ipam01' | jq -c '.results[0] // empty' 2>/dev/null || true)"
_m06o_ips="$(_m06o_nb "$_m06o_checks" 'ipam/ip-addresses/?q=m06-ipam01' \
  | jq -c '[.results[] | select((.dns_name // "") | startswith("m06-ipam01"))]' 2>/dev/null || true)"
if remote "$_m06o_pvehote" 'qm status 2063' >/dev/null 2>&1; then
  _m06o_ipnb="$(jq -r '.primary_ip4.address // empty' <<<"$_m06o_vm" 2>/dev/null || true)"
  check_output "NetBox : m06-ipam01 a une IP primaire dans 10.10.99.10-49" '^10\.10\.99\.[1-4][0-9]/24$' echo "$_m06o_ipnb"
  check_output "Proxmox : ipconfig0 de 2063 = l'adresse allouée par NetBox" "ip=${_m06o_ipnb//./\\.}(,|$)" _m06o_ipconfig
  check_cmd "NetBox : m06-ipam01 étiquetée env-m06, dans le cluster pve01" \
    jq -e '(.tags | map(.slug) | index("env-m06")) != null and .cluster.name == "pve01"' <<<"$_m06o_vm"
else
  skip "cohérence de m06-ipam01" "VM 2063 absente (détruite ?)"
  check_cmd "VM détruite : aucune adresse ne reste attribuée à m06-ipam01 dans NetBox" \
    jq -e 'length == 0' <<<"$_m06o_ips"
fi
