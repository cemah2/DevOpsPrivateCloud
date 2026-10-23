# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # programmes bash -c et filtres jq entre apostrophes
# check-S05.sh — F1-S05 « Reconstruire lb02 et dns02 depuis le code ». Lecture seule.
# « Reconstruite » = clé d'hôte SSH de la VM née APRÈS la marque de la phase 1 : premier commit de
# docs/day0/reference-avant.md sur main (S04), ou WB_F1_DEBUT (époque Unix) si tu l'as posé.
# Les clés d'hôte naissent au premier démarrage d'une instance (cloud-init) : une VM réparée en
# place les garde.
#
# Variables : WB_F1_DEBUT, WB_F1_ZONES (zones comparées entre dns01 et dns02), WB_F1_VIP_LB.

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S05 — Reconstruire lb02 et dns02 depuis le code"
require_cmd curl jq ssh dig

_f1_s05_vip="${WB_F1_VIP_LB:-10.10.70.200}"
read -r -a _f1_s05_zones <<<"${WB_F1_ZONES:-par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa}"

_f1_s05_marque="${WB_F1_DEBUT:-}"
if [[ -z "$_f1_s05_marque" ]]; then
  _f1_s05_ref="$(_f1p_doc_chemin '^reference-avant\.md$')" || _f1_s05_ref=""
  [[ -n "$_f1_s05_ref" ]] && _f1_s05_marque="$(_f1p_premier_commit "$_f1p_projet_doc" "$_f1_s05_ref" 2>/dev/null)" || _f1_s05_marque=""
fi
check_cmd "date de référence de la phase 1 connue (premier commit de docs/day0/reference-avant.md, ou WB_F1_DEBUT)" \
  test -n "$_f1_s05_marque"

# _f1_s05_vm NOM VMID — contrôles communs aux deux VMs reconstruites.
_f1_s05_vm() {
  local nom="$1" vmid="$2" ne fqdn="$1.par1.medisphere.internal" sc an
  check_cmd "$nom : VM $vmid démarrée sur $WB_PVE_HOST" bash -c '[[ "$1" == *"status: running"* ]]' _ "$(_f1p_pve "qm status $vmid")"
  if ! remote "$nom" true </dev/null >/dev/null 2>&1; then
    check_cmd "$nom : connexion SSH depuis adm01" false
    return 0
  fi
  ne="$(_f1p_hote_sortie "$nom" 'stat -c %W /etc/ssh/ssh_host_ed25519_key')" || ne=0
  check_cmd "$nom : instance née après le début de la phase 1 (VM recréée, pas réparée en place)" \
    bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ && "$1" -gt 0 && "$1" -gt "$2" ]]' _ "${ne:-0}" "${_f1_s05_marque:-0}"
  check_cmd "$nom : inscrit dans l'annuaire (keytab de l'hôte, comptes de l'annuaire résolus)" \
    _f1p_hote "$nom" "test -f /etc/ipa/default.conf && klist -k /etc/krb5.keytab | grep -q 'host/$fqdn@PAR1.MEDISPHERE.INTERNAL' && getent passwd lucas.martin >/dev/null"
  check_cmd "$nom : node_exporter supervisé (up = 1)" \
    bash -c '[[ "$1" == 1 ]]' _ "$(_f1p_prom_val "max(up{instance=~\"$nom([.:].*)?\"})")"
  sc="$(_f1p_prom_val "min(medisphere_conformite_score{instance=~\"$nom([.:].*)?\"})")" || sc=""
  an="$(_f1p_prom_val "min(medisphere_conformite_derniere_analyse_secondes{instance=~\"$nom([.:].*)?\"})")" || an=""
  check_cmd "$nom : score de conformité publié (${sc:-absent})" test -n "$sc"
  check_cmd "$nom : analyse de conformité faite après la reconstruction" \
    bash -c '[[ -n "$1" && -n "$2" ]] && (( ${1%.*} > $2 ))' _ "$an" "${_f1_s05_marque:-0}"
}

# --- lb02 -----------------------------------------------------------------------------------------
_f1_s05_vm lb02 1011
check_cmd "lb02 : HAProxy et keepalived actifs, configuration valide" \
  _f1p_hote lb02 'systemctl is-active --quiet haproxy && systemctl is-active --quiet keepalived && haproxy -c -f /etc/haproxy/haproxy.cfg'
check_cmd "lb02 : en secours VRRP (ne porte pas la VIP $_f1_s05_vip)" \
  _f1p_hote lb02 "! ip -4 -o addr show | grep -q ' $_f1_s05_vip/'"
check_cmd "lb01 : porte la VIP $_f1_s05_vip (maître, jamais basculé par la reconstruction)" \
  _f1p_hote lb01 "ip -4 -o addr show | grep -q ' $_f1_s05_vip/'"
check_http "le point d'entrée publié répond par la VIP (sso, HTTPS)" \
  "https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration" 200

# --- dns02 ----------------------------------------------------------------------------------------
_f1_s05_vm dns02 1008
for _f1_s05_z in "${_f1_s05_zones[@]}"; do
  _f1_s05_s1="$(_f1p_hote_sortie dns01 "dig +short +time=3 @127.0.0.1 -p 5300 $_f1_s05_z SOA" | awk '{print $3}')" || true
  _f1_s05_s2="$(_f1p_hote_sortie dns02 "dig +short +time=3 @127.0.0.1 -p 5300 $_f1_s05_z SOA" | awk '{print $3}')" || true
  check_cmd "zone $_f1_s05_z : dns02 sert le même numéro de série que dns01 (${_f1_s05_s1:-?} / ${_f1_s05_s2:-?})" \
    bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ "$_f1_s05_s1" "$_f1_s05_s2"
done
check_dns "récurseur de dns02 : résout un nom interne (git01)" git01.par1.medisphere.internal A '^10\.10\.20\.12$' 10.10.20.16
check_cmd "dns02 : serveur DHCP Kea actif" _f1p_hote dns02 'systemctl is-active --quiet isc-kea-dhcp4-server'

# --- Mesure et dette ---------------------------------------------------------------------------------
check_cmd "docs/day0/reconstruction-socle.md : durées mesurées et gestes manuels (dette) pour lb02 et dns02" \
  _f1p_doc '^reconstruction-socle\.md$' 'lb02' 'dns02' '[0-9]+ ?(min|h)' 'dette'
