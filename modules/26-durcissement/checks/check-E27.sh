# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E27.sh — M26-E27 « Pare-feu d'hôte de Cilium »
# À lancer depuis adm01. Lecture seule : cilium-config, politiques CiliumClusterwideNetworkPolicy
# d'hôte, étiquettes des nœuds, point de terminaison d'hôte de chaque agent (cilium-dbg endpoint list
# et endpoint config SANS argument : consultation, kubeconfig d'administration), VIP de l'API (SSH,
# ip addr), sessions BGP (cilium-dbg bgp peers, consultation), SSH et une connexion TCP refusée depuis
# adm01, santé (Thanos Query), fichiers sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E27 — Pare-feu d'hôte de Cilium"
require_cmd kubectl jq curl ssh

_M26_E27_ETIQ=medisphere.internal/pare-feu-hote

title "Activation"
check_output "cilium-config : enable-host-firewall = true" '^true$' _m26p_cilium_config enable-host-firewall
check_output "cilium-config : enable-extended-ip-protocols = true (VRRP des nœuds de contrôle)" '^true$' \
  _m26p_cilium_config enable-extended-ip-protocols
_m26_e27_vip=0
for _m26_e27_n in "${_M26P_CP[@]}"; do
  if remote "$_m26_e27_n" 'ip -br addr | grep -q "10\.10\.40\.200/"' >/dev/null 2>&1; then
    _m26_e27_vip=$((_m26_e27_vip + 1))
  fi
done
check_output "un seul nœud de contrôle porte la VIP 10.10.40.200 ($_m26_e27_vip trouvé(s))" '^1$' echo "$_m26_e27_vip"

title "Politiques d'hôte"
_m26_e27_ccnp="$(_m26p_json get ciliumclusterwidenetworkpolicies)"
for _m26_e27_p in hote-commun hote-plan-controle hote-travailleurs; do
  check_cmd "$_m26_e27_p : existe, sélectionne les nœuds étiquetés $_M26_E27_ETIQ=oui, règles d'entrée seulement" \
    _m26p_jq "$_m26_e27_ccnp" \
    'any(.items[]; .metadata.name == $p
         and (.spec.nodeSelector.matchLabels[$e] // "") == "oui"
         and ((.spec.ingress // []) | length) > 0
         and (.spec.egress == null) and (.spec.egressDeny == null))' \
    --arg p "$_m26_e27_p" --arg e "$_M26_E27_ETIQ"
done
check_cmd "hote-plan-controle autorise VRRP, etcd et 8443 (vault01-03 compris)" _m26p_jq "$_m26_e27_ccnp" \
  '[.items[] | select(.metadata.name == "hote-plan-controle") | .spec.ingress[]] as $r
   | ([$r[].toPorts[]?.ports[]? | select(.protocol == "VRRP")] | length > 0)
     and ([$r[].toPorts[]?.ports[]? | select(.port == "2380")] | length > 0)
     and ([$r[] | select(any(.fromCIDR[]?; startswith("10.10.20.2"))) | .toPorts[]?.ports[]? | select(.port == "8443")] | length > 0)'
_m26_e27_nodes="$(_m26p_json get nodes)"
check_cmd "les six nœuds portent l'étiquette $_M26_E27_ETIQ=oui" _m26p_jq "$_m26_e27_nodes" \
  '[.items[] | select((.metadata.labels[$e] // "") == "oui")] | length == 6' --arg e "$_M26_E27_ETIQ"
check_cmd "$_M26P_K8S : l'étiquette est dans cluster/noeuds.yaml (et gérée)" \
  _m26p_fichier_contient "$_M26P_K8S" cluster/noeuds.yaml 'etiquettes_gerees:.*pare-feu-hote' 'pare-feu-hote: *"?oui'

title "Application sur chaque nœud"
for _m26_e27_n in "${_M26P_NOEUDS[@]}"; do
  _m26_e27_id="$(_m26p_hote_id "$_m26_e27_n")"
  if [[ -z "$_m26_e27_id" ]]; then
    check_cmd "$_m26_e27_n : point de terminaison d'hôte lisible dans l'agent Cilium" false
    continue
  fi
  check_output "$_m26_e27_n : point de terminaison d'hôte $_m26_e27_id hors du mode audit (la politique s'applique)" \
    '^PolicyAuditMode[[:space:]]*:?[[:space:]]*Disabled' \
    bash -c 'grep -E "^PolicyAuditMode" <<<"$1"' _ "$(_m26p_agent "$_m26_e27_n" cilium-dbg endpoint config "$_m26_e27_id")"
done

title "Accès et santé"
for _m26_e27_n in "${_M26P_NOEUDS[@]}"; do
  check_ssh "$_m26_e27_n : SSH depuis adm01" "$_m26_e27_n" true
done
# Le kubelet écoute sur toutes les adresses ; depuis MGMT, seul le serveur d'API, Prometheus et
# metrics-server y ont droit : la connexion doit échouer (avant M26-E27, elle aboutissait).
# Contrôle significatif seulement si le nœud répond en SSH (sinon tout échouerait « pour rien »).
_m26_e27_refus() {
  remote "$1" true >/dev/null 2>&1 || return 1
  ! timeout "$WB_TIMEOUT" bash -c "exec 3<>/dev/tcp/$2/10250" 2>/dev/null
}
check_cmd "k8s-w03 : le kubelet (10250) est refusé depuis adm01 (SSH, lui, répond)" _m26_e27_refus k8s-w03 "${_M26P_IP[k8s-w03]}"
check_cmd "k8s-cp01 : le kubelet (10250) est refusé depuis adm01 (SSH, lui, répond)" _m26_e27_refus k8s-cp01 "${_M26P_IP[k8s-cp01]}"
check_cmd "six nœuds Ready" _m26p_jq "$_m26_e27_nodes" \
  '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length == 6'
check_output "aucune cible node-exporter ou kubelet en échec dans Prometheus" '^0$' \
  _m26p_nb 'up{job=~"node-exporter|kubelet"} == 0'
for _m26_e27_n in "${_M26P_TRAV[@]}"; do
  check_output "$_m26_e27_n : deux sessions BGP établies" '^2$' \
    bash -c 'grep -ci "established" <<<"$1" || true' _ "$(_m26p_agent "$_m26_e27_n" cilium-dbg bgp peers)"
done

title "Documentation"
check_cmd "$_M26P_DOC : RB-264 sur main (audit, application, retour arrière par la console)" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement/runbooks 'RB-264' 30 'audit' 'crictl' 'pare-feu-hote'
check_cmd "$_M26P_DOC : matrice des flux du cluster, section des entrées des nœuds" \
  _m26p_doc_present "$_M26P_DOC" docs/kubernetes/reseau 'matrice-flux-cluster\.md$' 10 'entr(é|e)es des n(œ|oe|o)uds' '10250' 'VRRP'
