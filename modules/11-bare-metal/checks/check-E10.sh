# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E10.sh — M11-E10 : MAAS : inventorier et déployer des machines
# À lancer depuis adm01, AVANT d'éteindre maas01 (contrôle de la partie MAAS), puis APRÈS (retour
# à Kea). Lecture seule : API de MAAS en lecture, pare-feu Proxmox lu en root, Kea, relais.

# shellcheck source=_m11-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-operationnel.sh"

title "M11-E10 — MAAS : inventorier et déployer des machines"
require_cmd jq curl

# --- Préparation : fiche, flux --------------------------------------------------------------------------------
check_cmd "documentation : fiche CHG-1215 dans docs/socle/changements/" \
  bash -c 'ls "$1"/docs/socle/changements/CHG-1215* >/dev/null 2>&1' _ "${WB_DEPOT:-$HOME/medisphere}"
_m11o_pf="$(_m11o_contenu_main "$_M11O_PROJET_ANSIBLE" inventories/lab/host_vars/gw01/pare_feu.yml)"
check_output "matrice de la bordure (main) : maas01 → pve01 en TCP 8006" \
  '(MAAS|maas|10\.10\.60\.11).*ports: 8006|ports: 8006.*(MAAS|maas)' echo "$_m11o_pf"
_m11o_ipset="$(remote "$_M11O_PVE" 'pvesh get /cluster/firewall/ipset/maas --output-format json' 2>/dev/null || true)"
check_output "pare-feu Proxmox : IPSet maas = 10.10.60.11" '^10\.10\.60\.11(/32)?$' jq -r '[.[].cidr] | join(" ")' <<<"$_m11o_ipset"
check_cmd "pare-feu Proxmox : règle d'entrée 8006 depuis l'IPSet maas" \
  bash -c 'jq -e "[.[] | select(.type == \"in\" and .action == \"ACCEPT\" and ((.source // \"\") | test(\"^\\\\+(dc/)?maas$\")) and ((.dport // \"\") | tostring | test(\"8006\")))] | length >= 1" <<<"$1"' _ \
  "$(remote "$_M11O_PVE" 'pvesh get /cluster/firewall/rules --output-format json' 2>/dev/null || true)"

# --- La partie MAAS (seulement si MAAS répond) -------------------------------------------------------------------
if curl -sf --max-time "$WB_TIMEOUT" "$_M11O_MAAS_URL/api/2.0/version/" >/dev/null 2>&1; then
  _m11o_machines="$(_m11o_maas 'machines/' || true)"
  for _m11o_l in "bm01 02:4d:53:60:00:01" "bm03 02:4d:53:60:00:03"; do
    read -r _m11o_nom _m11o_mac <<<"$_m11o_l"
    _m11o_m="$(jq -c --arg m "$_m11o_mac" '[.[] | select([.interface_set[]?.mac_address | ascii_downcase] | index($m))][0] // empty' <<<"$_m11o_machines" 2>/dev/null || true)"
    if [[ -z "$_m11o_m" ]]; then
      _ko "MAAS : aucune machine avec la MAC de $_m11o_nom ($_m11o_mac)"
      continue
    fi
    _m11o_id="$(jq -r .system_id <<<"$_m11o_m")"
    check_output "MAAS : $_m11o_nom pilotée par le pilote proxmox" '^proxmox$' jq -r '.power_type' <<<"$_m11o_m"
    _m11o_pp="$(_m11o_maas "machines/$_m11o_id/?op=power_parameters" || true)"
    check_output "MAAS : $_m11o_nom — vérification TLS activée (power_verify_ssl)" '^y$' jq -r '.power_verify_ssl // empty' <<<"$_m11o_pp"
    check_output "MAAS : $_m11o_nom — compte wb-maas@pve et jeton maas" '^wb-maas@pve maas$' \
      jq -r '"\(.power_user // "") \(.power_token_name // "" | sub("^wb-maas@pve!"; ""))"' <<<"$_m11o_pp"
    _m11o_ev="$(_m11o_maas "events/?op=query&hostname=$(jq -r .hostname <<<"$_m11o_m")&limit=500" || true)"
    check_cmd "MAAS : $_m11o_nom a été mise en service puis déployée (journal des évènements)" \
      bash -c 'jq -e "[.events[]?.type] | any(test(\"ommission\")) and any(test(\"^Deployed$\"))" <<<"$1"' _ "$_m11o_ev"
    check_output "MAAS : $_m11o_nom libérée en fin d'essai (Ready)" '^Ready$' jq -r '.status_name' <<<"$_m11o_m"
  done
  check_cmd "MAAS : DHCP désactivé sur tous ses VLAN (fin d'essai)" \
    bash -c 'jq -e "[.[].vlans[]? | select(.dhcp_on == true)] | length == 0" <<<"$1"' _ "$(_m11o_maas 'fabrics/' || true)"
else
  skip "partie MAAS (machines, pilote, déploiement)" "MAAS ne répond pas : lance ce contrôle AVANT d'arrêter maas01"
  check_cmd "maas01 arrêtée ou MAAS arrêté" \
    bash -c '! curl -sf --max-time 3 "$1/api/2.0/version/" >/dev/null 2>&1' _ "$_M11O_MAAS_URL"
fi

# --- Retour à Kea ------------------------------------------------------------------------------------------------
for _m11o_h in dns01 dns02; do
  check_cmd "$_m11o_h : Kea sert de nouveau le sous-réseau 60 (next-server 10.10.60.10)" \
    jq -e '.arguments.Dhcp4.subnet4[] | select(.id == 60) | .["next-server"] == "10.10.60.10"' <<<"$(_m11o_kea "$_m11o_h")"
done
for _m11o_h in gw01 gw02; do
  check_ssh "$_m11o_h : le relais couvre de nouveau ens19.60" "$_m11o_h" \
    'grep -hqs "^interface=ens19\.60$" /etc/dnsmasq.d/*.conf && systemctl is-active --quiet dnsmasq'
done
check_cmd "bilan de l'essai (~/m11/e10/bilan.md)" test -s "$HOME/m11/e10/bilan.md"
