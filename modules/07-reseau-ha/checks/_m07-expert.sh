# shellcheck shell=bash
# _m07-expert.sh — fonctions partagées par les vérifications du palier 4 du module 07 (check-E35 à
# check-E44). Sourcé par ces scripts, jamais lancé seul. Lecture seule : commandes d'observation
# (ip, ss, nft list, vtysh show, wg show, ovs-appctl … /show, socket d'administration de HAProxy en
# « show stat »), exécutées par SSH (hôtes du socle) ou par l'agent QEMU depuis pve01 (VMs de la
# maquette : indépendant des adresses DHCP et des pannes réseau).
# Préfixe _m07x_ : évite les collisions quand check-E43 charge plusieurs checks.

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m07x_vmid=([net01]=2070 [spine01]=2071 [spine02]=2072 [leaf01]=2073 [leaf02]=2074
  [srv01]=2075 [srv02]=2076 [lyo-gw01]=2077 [lyo-pc01]=2078 [hap01]=2079)
# shellcheck disable=SC2034
declare -A _m07x_boucle=([spine01]=10.10.255.1 [spine02]=10.10.255.2 [leaf01]=10.10.255.11
  [leaf02]=10.10.255.12 [srv01]=10.10.255.21 [srv02]=10.10.255.22)

# _m07x_sur HÔTE 'commande' — exécute la commande (bash -c) en root sur l'hôte ; affiche sa sortie
# standard, renvoie son code. Maquette : agent QEMU (qm guest exec) ; socle : SSH + sudo -n.
_m07x_sur() {
  local h="$1" cmd="$2" sortie rc
  if [[ -n "${_m07x_vmid[$h]:-}" ]]; then
    sortie="$(remote "$WB_PVE_HOST" "qm guest exec ${_m07x_vmid[$h]} --timeout 60 -- bash -c $(printf '%q' "$cmd")" 2>/dev/null)" || return 1
    jq -r '."out-data" // empty' <<<"$sortie" 2>/dev/null
    rc="$(jq -r 'if (.exited == 1 or .exited == true) then (.exitcode // 1) else 124 end' <<<"$sortie" 2>/dev/null)" || rc=1
    return "${rc:-1}"
  fi
  remote "$h" "sudo -n bash -c $(printf '%q' "$cmd")"
}

# _m07x_ok HÔTE 'commande' — idem, sans sortie (pour check_cmd).
_m07x_ok() { _m07x_sur "$@" >/dev/null 2>&1; }

# _m07x_existe HÔTE — VM de la maquette dont l'agent répond, ou hôte du socle joignable en SSH.
_m07x_existe() {
  if [[ -n "${_m07x_vmid[$1]:-}" ]]; then
    remote "$WB_PVE_HOST" "qm guest cmd ${_m07x_vmid[$1]} ping" >/dev/null 2>&1
  else
    remote "$1" true >/dev/null 2>&1
  fi
}

# _m07x_vip_sur HÔTE ADRESSE — l'hôte porte l'adresse.
_m07x_vip_sur() { _m07x_ok "$1" "ip -4 -o addr show | grep -q ' $2/'"; }

# _m07x_un_seul_maitre HÔTE_A HÔTE_B VIP — exactement un des deux porte la VIP.
_m07x_un_seul_maitre() {
  local n=0
  _m07x_vip_sur "$1" "$3" && n=$((n + 1))
  _m07x_vip_sur "$2" "$3" && n=$((n + 1))
  ((n == 1))
}

# _m07x_pairs HÔTE [AS] — pairs BGP IPv4 : « pair état AS pfxRcd pfxSnt nom_d_hôte » par ligne.
_m07x_pairs() {
  _m07x_sur "$1" "vtysh -c 'show bgp ipv4 unicast summary json'" 2>/dev/null | jq -r --arg as "${2:-}" '
    (.peers // .ipv4Unicast.peers // {}) | to_entries[]
    | select($as == "" or ((.value.remoteAs | tostring) == $as))
    | [.key, (.value.state // "?"), (.value.remoteAs // "?" | tostring),
       (.value.pfxRcd // 0 | tostring), (.value.pfxSnt // 0 | tostring),
       (.value.hostname // "-")] | join(" ")' 2>/dev/null
}

# _m07x_sauts HÔTE PRÉFIXE — nombre de sauts (interfaces) de la route.
_m07x_sauts() {
  _m07x_sur "$1" "ip -4 route show $2 | grep -oE 'dev [^ ]+' | sort -u | wc -l" 2>/dev/null
}

# _m07x_pas_d_icmp_jete HÔTE — aucune règle nftables qui jette ou rejette de l'ICMPv4 en dehors
# d'une limitation de débit (les « limit rate over … drop » sont admises).
_m07x_pas_d_icmp_jete() {
  _m07x_ok "$1" "! nft list ruleset 2>/dev/null | grep -E 'icmp|destination-unreachable|frag-needed' | grep -v 'icmpv6' | grep -v 'limit rate over' | grep -Eq '(drop|reject)'"
}

# _m07x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M07-* si aucune) n'est marquée.
_m07x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M07-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M07-$e" ]] || return 1
  done
}

# _m07x_sysctl_force HÔTE CLÉ VALEUR — un fichier de configuration sysctl force CLÉ à VALEUR (piège
# qui reviendrait au prochain redémarrage).
_m07x_sysctl_force() {
  _m07x_ok "$1" "grep -rhsE '^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*\$' /etc/sysctl.conf /etc/sysctl.d/ | grep -q ."
}
