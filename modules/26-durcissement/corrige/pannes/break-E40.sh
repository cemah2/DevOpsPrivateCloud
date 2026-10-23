# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E40.sh — M26-E40 « Panne : des nœuds ne se parlent plus »
#
# Sur UN SEUL travailleur (jamais un nœud de contrôle, jamais plus d'un nœud) :
#   1. « essai d'une politique resserrée » : l'étiquette medisphere.internal/pare-feu-hote est retirée du
#      nœud (les politiques hote-* d'E27 ne le sélectionnent plus) et une CiliumClusterwideNetworkPolicy
#      posée à la main avec un nodeSelector sur ce nœud reprend leurs flux… sauf la santé Cilium (4240,
#      ICMP) : le nœud devient « injoignable » pour les autres (cilium_unreachable_nodes) ;
#   2. le pare-feu local (nftables) du nœud filtre le port WireGuard 51871/UDP : le chiffrement entre ce
#      nœud et les autres ne s'établit plus ;
#   3. la MTU de eth0 du nœud est incohérente (1400) : les gros paquets tombent (symptôme intermittent).
#
# Annulation : la CCNP par kubectl depuis adm01 (indépendant du nœud) ; nftables et MTU par SSH, avec
# l'agent QEMU en secours. Jamais sur un nœud de contrôle.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E40_NOEUD="${WB_M26_NOEUD:-k8s-w03}"

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

_e40_injecter() {
  local n="$1"
  m26_kube_sain || return 1
  wb_kubectl get node "$_E40_NOEUD" >/dev/null 2>&1 || { wb_avert "nœud $_E40_NOEUD introuvable"; return 1; }
  # Garde-fou (WB_M26_NOEUD) : jamais un nœud de contrôle (etcd, VIP de l'API).
  if [[ -n "$(wb_kubectl get node "$_E40_NOEUD" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null)" ]] \
     || wb_kubectl get node "$_E40_NOEUD" -o jsonpath='{.metadata.labels}' 2>/dev/null | grep -q 'node-role.kubernetes.io/control-plane'; then
    wb_avert "$_E40_NOEUD est un nœud de contrôle : M26-E40 ne vise qu'un travailleur (WB_M26_NOEUD)"
    return 1
  fi
  m26_ecrire E40 variante "$n"
  case "$n" in
    1)
      # Exige le pare-feu d'hôte (E27) : sans lui, une politique de nœud n'a aucun effet.
      [[ "$(wb_kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.enable-host-firewall}' 2>/dev/null)" == true ]] \
        || return 10
      m26_ecrire E40 etiquette "$(wb_kubectl get node "$_E40_NOEUD" -o jsonpath='{.metadata.labels.medisphere\.internal/pare-feu-hote}' 2>/dev/null)"
      m26_sauver_objet E40 ciliumclusterwidenetworkpolicies wb-pare-feu-hote-essai
      wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: wb-pare-feu-hote-essai
  annotations: {medisphere.internal/auteur: lucas.martin, medisphere.internal/ticket: "PLAT-2740"}
  labels: {medisphere.internal/panne: M26-E40}
spec:
  description: "essai de pare-feu d'hote resserre (reprend hote-commun sans la sante Cilium 4240)"
  nodeSelector:
    matchLabels: {kubernetes.io/hostname: $_E40_NOEUD}
  ingress:
    - fromEntities: [remote-node]
      toPorts: [{ports: [{port: "8472", protocol: UDP}, {port: "51871", protocol: UDP}]}]
    - fromEntities: [kube-apiserver]
      toPorts: [{ports: [{port: "10250", protocol: TCP}]}]
    - fromEndpoints: [{matchLabels: {k8s:io.kubernetes.pod.namespace: kube-system, k8s:app.kubernetes.io/name: metrics-server}}]
      toPorts: [{ports: [{port: "10250", protocol: TCP}]}]
    - fromEndpoints: [{matchLabels: {k8s:io.kubernetes.pod.namespace: supervision}}]
      toPorts: [{ports: [{port: "9100", protocol: TCP}, {port: "9962", protocol: TCP}, {port: "10250", protocol: TCP}]}]
    - fromEndpoints: [{matchLabels: {k8s:io.kubernetes.pod.namespace: kube-system, k8s:k8s-app: hubble-relay}}]
      toPorts: [{ports: [{port: "4244", protocol: TCP}]}]
    - fromCIDR: [10.10.10.0/24, 10.10.20.15/32]
      toPorts: [{ports: [{port: "22", protocol: TCP}]}]
    - fromCIDR: [10.10.40.2/32, 10.10.40.3/32]
      toPorts: [{ports: [{port: "179", protocol: TCP}]}]
EOF
      wb_kubectl label node "$_E40_NOEUD" medisphere.internal/pare-feu-hote- >/dev/null 2>&1 || true
      m26_attendre 240 _e40_effet 1 || { _e40_defaire 1; return 10; }
      ;;
    2)
      m26_hote_sain "$_E40_NOEUD" || return 10
      m26_wb_exec "$_E40_NOEUD" >/dev/null <<'EOF' || return 1
nft add table inet wb_e40 2>/dev/null || true
nft add chain inet wb_e40 entree '{ type filter hook input priority filter - 20 ; policy accept ; }' 2>/dev/null || true
nft add rule inet wb_e40 entree udp dport 51871 counter drop comment "PLAT-2740 (Lucas) : fermer WireGuard"
journal "nftables local : UDP 51871 (WireGuard Cilium) filtré en entrée"
EOF
      m26_ecrire E40 cible "$_E40_NOEUD"
      ;;
    3)
      m26_hote_sain "$_E40_NOEUD" || return 10
      m26_wb_exec "$_E40_NOEUD" >/dev/null <<'EOF' || return 1
i=eth0
mtu="$(cat /sys/class/net/$i/mtu 2>/dev/null)"
[ -n "$mtu" ] || { echo "interface $i absente" >&2; exit 1; }
echo "$mtu" > "$WB_DIR/$WB_EX.mtu-$i"
ip link set dev "$i" mtu 1400
journal "MTU de $i abaissée de $mtu à 1400"
EOF
      m26_ecrire E40 cible "$_E40_NOEUD"
      ;;
  esac
  m26_journal E40 "variante $n posée sur $_E40_NOEUD"
}

_e40_effet() {
  case "$1" in
    # Effet réel : l'agent d'un NŒUD DE CONTRÔLE voit le nœud injoignable par la sonde de santé. Pas
    # « ds/cilium » (premier pod venu, peut-être celui du nœud cassé) ni un autre travailleur : avec le
    # chiffrement nœud à nœud (E26), le trafic d'hôte entre travailleurs arrive par cilium_wg0, où le
    # pare-feu d'hôte ne s'applique pas ; les nœuds de contrôle, exclus du chiffrement, passent par eth0.
    1) local p
       p="$(wb_kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=k8s-cp01 \
             -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || p=""
       [[ -n "$p" ]] && wb_kubectl get ciliumclusterwidenetworkpolicies wb-pare-feu-hote-essai >/dev/null 2>&1 \
         && wb_kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-health status --verbose 2>/dev/null \
            | grep -A8 "$_E40_NOEUD" | grep -qiE 'unreachable|connection refused|timed? ?out|i/o' ;;
    2) m26_ssh "$_E40_NOEUD" 'nft list table inet wb_e40' >/dev/null 2>&1 ;;
    3) [[ "$(m26_ssh "$_E40_NOEUD" 'cat /sys/class/net/eth0/mtu' 2>/dev/null)" == 1400 ]] ;;
  esac
}

verifier_E40() { _e40_effet "$WB_VAR"; }

_e40_defaire() {
  case "$1" in
    1)
      m26_restaurer_objet E40 ciliumclusterwidenetworkpolicies wb-pare-feu-hote-essai
      # L'étiquette du nœud revient à sa valeur d'avant (gérée par cluster/noeuds.yaml, E27).
      local e; e="$(m26_lire E40 etiquette)"
      if [[ -n "$e" ]]; then
        wb_kubectl label node "$_E40_NOEUD" "medisphere.internal/pare-feu-hote=$e" --overwrite >/dev/null 2>&1 || true
      fi
      m26_oublier E40 etiquette
      ;;
    2)
      WB_EX=M26-E40 m26_wb_exec_invite "$_E40_NOEUD" >/dev/null <<'EOF' || wb_avert "annulation nftables incomplète sur le nœud"
nft delete table inet wb_e40 2>/dev/null || true
journal "annulation : table nftables wb_e40 retirée (agent QEMU)"
EOF
      ;;
    3)
      WB_EX=M26-E40 m26_wb_exec_invite "$_E40_NOEUD" >/dev/null <<'EOF' || wb_avert "annulation MTU incomplète sur le nœud"
i=eth0
m="$(cat "$WB_DIR/$WB_EX.mtu-$i" 2>/dev/null)"
[ -n "$m" ] && ip link set dev "$i" mtu "$m" && rm -f "$WB_DIR/$WB_EX.mtu-$i"
journal "annulation : MTU de $i rétablie à ${m:-?} (agent QEMU)"
EOF
      ;;
  esac
}

annuler_E40() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-3]$ ]] || v="$(m26_lire E40 variante)"
  [[ -n "$v" ]] && _e40_defaire "$v"
  m26_oublier E40 variante
  m26_oublier E40 cible
  m26_journal E40 "annulation"
}

resume_E40() { echo "Un travailleur ne communique plus normalement avec les autres (santé Cilium, WireGuard ou MTU)."; }

symptome_E40() {
  wb_symptome "Ticket INC-5340 — De : Nadia Roussel" \
    "Depuis la vague « réseau » du durcissement (pare-feu d'hôte, chiffrement WireGuard), des pods d'un" \
    "nœud n'arrivent plus à joindre ceux des autres : des connexions tombent, des sondes échouent par" \
    "intermittence, Hubble montre des paquets perdus. Un seul travailleur semble concerné." \
    "Un nœud à la fois, un retour arrière écrit : ne touche pas tout le cluster." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 26 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E40 3 "$@"; }
fi
