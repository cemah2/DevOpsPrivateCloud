# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M15-E42 « Panne : les pods ne se joignent plus entre nœuds »
#
# Cible : UN travailleur tiré au hasard (k8s-w01 à w03), jamais un nœud de contrôle.
# Variantes :
#   1. pare-feu du nœud : table nftables « inet wb_durcissement » (script de durcissement d'InfoGér)
#      qui jette en entrée UDP 8472 (VXLAN) et UDP 51871 (WireGuard de Cilium) ; repli sur
#      iptables (backend nft) si la commande nft est absente ;
#   2. agent Cilium mal configuré sur ce nœud : CiliumNodeConfig « essai-tunnel » (kube-system) qui
#      passe tunnel-port à 8473 sur ce seul nœud, puis redémarrage de son agent : les tunnels des
#      deux côtés ne se comprennent plus ;
#   3. interface de chiffrement cilium_wg0 (ou, sans WireGuard, cilium_vxlan) mise « down » sur le
#      nœud (même script de durcissement : « interfaces inconnues désactivées »).
# Rien n'est écrit sur le disque du nœud : un redémarrage du nœud efface les variantes 1 et 3.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E42_CNC=essai-tunnel

_e42_autre() {
  local n
  for n in "${_M15_TRAVAILLEURS[@]}"; do
    [[ "$n" != "$1" ]] && { printf '%s\n' "$n"; return 0; }
  done
  return 1
}

# _e42_coupe — le témoin d'un autre travailleur ne joint plus celui du nœud ciblé (3 essais).
_e42_coupe() {
  local cible autre i
  cible="$(m15_lire E42 noeud)"
  autre="$(_e42_autre "$cible")" || return 1
  for i in 1 2 3; do
    m15_joindre "$autre" "$cible" && return 1
    sleep 2
  done
  return 0
}

_m15E42_une() {
  local n="$1" cible
  cible="$(m15_lire E42 noeud)"
  if [[ -z "$cible" ]]; then
    cible="${_M15_TRAVAILLEURS[RANDOM % ${#_M15_TRAVAILLEURS[@]}]}"
    m15_ecrire E42 noeud "$cible"
  fi
  case "$n" in
    1)
      wb_exec "$cible" <<'EOF' || return 1
if command -v nft >/dev/null 2>&1; then
  nft list table inet wb_durcissement >/dev/null 2>&1 && exit 1
  nft -f - <<'NFT' || exit 1
table inet wb_durcissement {
  chain entree {
    type filter hook input priority filter - 5; policy accept;
    udp dport 8472 counter drop comment "durcissement InfoGer : ports non documentes"
    udp dport 51871 counter drop comment "durcissement InfoGer : ports non documentes"
  }
}
NFT
  echo nft > "$WB_DIR/$WB_EX.outil"
else
  command -v iptables >/dev/null 2>&1 || exit 1
  iptables -I INPUT -p udp --dport 8472 -m comment --comment wb-durcissement -j DROP || exit 1
  iptables -I INPUT -p udp --dport 51871 -m comment --comment wb-durcissement -j DROP || exit 1
  echo iptables > "$WB_DIR/$WB_EX.outil"
fi
journal "ports 8472 et 51871 jetés en entrée"
EOF
      ;;
    2)
      m15_k -n kube-system get cm cilium-config -o jsonpath='{.data.tunnel-protocol}' 2>/dev/null | grep -q . \
        || m15_k -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}' 2>/dev/null | grep -qx tunnel \
        || return 10
      m15_sauver ciliumnodeconfig "$_E42_CNC" kube-system
      m15_k apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  name: $_E42_CNC
  namespace: kube-system
  annotations:
    medisphere.fr/demande: "PLAT-1629 : essai de port de tunnel (à retirer après l'essai)"
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: $cible
  defaults:
    tunnel-port: "8473"
EOF
      m15_k -n kube-system delete pod -l k8s-app=cilium --field-selector "spec.nodeName=$cible" --wait=false >/dev/null 2>&1 || return 1
      sleep 20
      m15_k -n kube-system wait pod -l k8s-app=cilium --field-selector "spec.nodeName=$cible" \
        --for=condition=Ready --timeout=180s >/dev/null 2>&1 || true
      ;;
    3)
      wb_exec "$cible" <<'EOF' || return 10
for i in cilium_wg0 cilium_vxlan; do
  if ip link show "$i" >/dev/null 2>&1; then
    ip link show "$i" | grep -q 'state DOWN' && exit 1
    ip link set dev "$i" down || exit 1
    echo "$i" > "$WB_DIR/$WB_EX.interface"
    journal "interface $i mise down"
    exit 0
  fi
done
exit 1
EOF
      ;;
  esac
  m15_journal E42 "variante $n posée sur $cible"
}

panne_E42_v1() { m15_preparer && m15_essayer E42 3 1; }
panne_E42_v2() { m15_preparer && m15_essayer E42 3 2; }
panne_E42_v3() { m15_preparer && m15_essayer E42 3 3; }

verifier_E42() { m15_attendre 90 _e42_coupe; }

annuler_E42() {
  local cible
  cible="$(m15_lire E42 noeud)"
  if [[ -n "$cible" ]]; then
    wb_exec "$cible" <<'EOF' || wb_avert "annulation : état du nœud $cible à vérifier (pare-feu, interfaces)"
if command -v nft >/dev/null 2>&1 && nft list table inet wb_durcissement >/dev/null 2>&1; then
  nft delete table inet wb_durcissement
fi
if command -v iptables >/dev/null 2>&1; then
  while iptables -D INPUT -p udp --dport 8472 -m comment --comment wb-durcissement -j DROP 2>/dev/null; do :; done
  while iptables -D INPUT -p udp --dport 51871 -m comment --comment wb-durcissement -j DROP 2>/dev/null; do :; done
fi
if [ -f "$WB_DIR/$WB_EX.interface" ]; then
  i="$(cat "$WB_DIR/$WB_EX.interface")"
  if ip link show "$i" 2>/dev/null | grep -q 'state DOWN'; then ip link set dev "$i" up; fi
fi
rm -f "$WB_DIR/$WB_EX.interface" "$WB_DIR/$WB_EX.outil"
journal "annulation"
EOF
  fi
  if m15_k -n kube-system get ciliumnodeconfig "$_E42_CNC" >/dev/null 2>&1; then
    m15_k -n kube-system delete ciliumnodeconfig "$_E42_CNC" >/dev/null 2>&1 || true
    if [[ -n "$cible" ]]; then
      m15_k -n kube-system delete pod -l k8s-app=cilium --field-selector "spec.nodeName=$cible" >/dev/null 2>&1 || true
    fi
  fi
  m15_oublier E42
}

resume_E42() {
  echo "Les pods d'un des travailleurs ne joignent plus ceux des autres nœuds (MédiAgenda échoue par intermittence)."
}

symptome_E42() {
  wb_symptome "Ticket INC-4248 — De : Nadia Roussel" \
    "Depuis le passage d'InfoGér ce matin (« durcissement des serveurs », sans ticket de" \
    "changement), MédiAgenda en recette échoue une requête sur trois environ, sans logique" \
    "apparente, et la sonde de supervision voit des délais dépassés. Tous les nœuds sont Ready," \
    "tous les pods sont Running. Les témoins du palier sont là pour t'aider :" \
    "kubectl -n $_M15_NS_TEMOINS get pods -o wide" \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 15 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E42 3 "$@"; }
fi
