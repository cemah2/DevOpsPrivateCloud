# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M15-E08 : Remplacer kube-proxy par Cilium
# À lancer depuis adm01. Lecture seule : objets de kube-system (wb-checks), règles netfilter des nœuds
# lues en SSH (sudo -n, iptables-save / nft list ruleset), fichiers sur main (API GitLab en GET),
# requêtes HTTP vers le NodePort echo-np.

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E08 — Remplacer kube-proxy par Cilium"
require_cmd kubectl jq yq curl ssh

# --- kube-proxy a disparu --------------------------------------------------------------------------------
check_cmd "DaemonSet kube-system/kube-proxy supprimé" _m15d_absent -n kube-system daemonset kube-proxy
check_cmd "ConfigMap kube-system/kube-proxy supprimée" _m15d_absent -n kube-system configmap kube-proxy
_m15d_e08_kp="$(kube -n kube-system get pods -l k8s-app=kube-proxy -o name 2>/dev/null || echo erreur)"
check_cmd "plus aucun pod kube-proxy" test -z "$_m15d_e08_kp"

# --- Cilium fait le travail -----------------------------------------------------------------------------------
check_output "cilium-config : kube-proxy-replacement = true" '^true$' _m15d_cilium_cfg kube-proxy-replacement
check_output "serveur de santé compatible kube-proxy sur 10256" ':10256$' _m15d_cilium_cfg kube-proxy-replacement-healthz-bind-address
check_output "l'agent joint l'API par la VIP (k8s-service-host), indispensable sans kube-proxy" \
  '^(k8s-api\.par1\.medisphere\.internal|10\.10\.40\.200)$' _m15d_cilium_cfg k8s-service-host
_m15d_e08_ds="$(_m15d_get -n kube-system daemonset cilium)"
check_cmd "agents Cilium prêts et à jour sur tous les nœuds (${#_M15D_NOEUDS[@]})" _m15d_json "$_m15d_e08_ds" \
  '.status.numberReady == $n and .status.desiredNumberScheduled == $n and (.status.updatedNumberScheduled // 0) == $n' \
  --argjson n "${#_M15D_NOEUDS[@]}"
check_cmd "chaque agent Cilium a redémarré après la dernière modification de cilium-config" _m15d_agents_a_jour
# Le serveur de santé (10256) n'existe que si le remplacement est actif dans l'agent ; kube-proxy, qui
# écoutait sur le même port, a disparu (contrôles ci-dessus).
for _m15d_e08_n in "${_M15D_WORKERS[@]}"; do
  _m15d_e08_ip="$(_m15d_ip_noeud "$_m15d_e08_n")"
  _m15d_e08_c="$(_m15d_http_code "http://$_m15d_e08_ip:10256/healthz")"
  check_cmd "$_m15d_e08_n : /healthz du remplacement de kube-proxy répond sur 10256 (HTTP $_m15d_e08_c)" \
    test "$_m15d_e08_c" = 200
done

# --- Les nœuds n'ont plus de règles de kube-proxy ---------------------------------------------------------------
for _m15d_e08_n in "${_M15D_NOEUDS[@]}"; do
  _m15d_e08_r="$(_m15d_regles_noeud "$_m15d_e08_n")"
  check_cmd "$_m15d_e08_n : règles lisibles (chaînes CILIUM présentes) et plus aucune chaîne KUBE-SERVICES / KUBE-SVC / KUBE-NODEPORTS" \
    bash -c 'grep -q "CILIUM" <<<"$1" && ! grep -qE "KUBE-(SERVICES|SVC-|SEP-|NODEPORTS|EXT-)" <<<"$1"' _ "$_m15d_e08_r"
done

# --- kubeadm ne réinstallera pas kube-proxy ---------------------------------------------------------------------
_m15d_e08_cc="$(kube -n kube-system get configmap kubeadm-config -o json 2>/dev/null | jq -r '.data.ClusterConfiguration // ""' 2>/dev/null || true)"
_m15d_e08_proxy_off() {
  _m15d_yq_vrai 'select(.kind == "ClusterConfiguration") | .proxy.disabled == true' "$1"
}
check_cmd "ConfigMap kubeadm-config : proxy.disabled = true (kubeadm upgrade sautera kube-proxy)" \
  _m15d_e08_proxy_off "$_m15d_e08_cc"
_m15d_e08_kc="$(_m15d_contenu_main "$_M15D_PROJET_K8S" cluster/kubeadm-config.yaml)"
check_cmd "cluster/kubeadm-config.yaml du dépôt : proxy.disabled = true" _m15d_e08_proxy_off "$_m15d_e08_kc"
check_cmd "cluster/kubeadm-config.yaml du dépôt : plus de document KubeProxyConfiguration" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "^kind:[[:space:]]*KubeProxyConfiguration" <<<"$1"' _ "$_m15d_e08_kc"

# --- Le code ----------------------------------------------------------------------------------------------------
_m15d_e08_values="$(_m15d_contenu_main "$_M15D_PROJET_K8S" composants/cilium/values.yaml)"
check_cmd "composants/cilium/values.yaml du dépôt : kubeProxyReplacement true" \
  _m15d_yq_vrai '.kubeProxyReplacement == true or .kubeProxyReplacement == "true"' "$_m15d_e08_values"
check_cmd "outils/nettoyer-regles-kube-proxy.sh (ou équivalent) sur main de plateforme/k8s" \
  _m15d_depot_a 'kube-?proxy' "$_M15D_PROJET_K8S" outils
check_cmd "fiche de changement CHG-1608 dans docs/kubernetes/changements/ (sur main)" \
  _m15d_depot_a '^CHG-1608' "$_M15D_PROJET_DOC" docs/kubernetes/changements

# --- Les Services marchent toujours ------------------------------------------------------------------------------
mapfile -t _m15d_e08_noeuds < <(_m15d_noeuds_echo)
_m15d_e08_ip="$(_m15d_ip_noeud "${_m15d_e08_noeuds[0]:-k8s-w01}")"
check_http "NodePort echo-np servi par Cilium ($_m15d_e08_ip:30880)" "http://$_m15d_e08_ip:30880/hostname" 200
