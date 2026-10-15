# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E46.sh — M15-E46 « Mini-projet : réseau Kubernetes MédiSphère v1 » : contrôle global.
# Rejoue les contrôles d'état de M15-E35 à M15-E42, puis vérifie ce qui fait « k8s-reseau-v1 » :
# remplacement de kube-proxy, chiffrement, Hubble, politiques des deux environnements, publication
# externe par lb01/lb02, documentation, flux de la bordure, m15-essai détruite, étiquette.
# Lecture seule. Prend quelques minutes.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

_m15_e46_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m15_e46_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m15_e46_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m15_e46_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m15_e46_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m15_e46_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m15_e46_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m15_e46_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m15_e46_checks/check-E42.sh"

title "M15-E46 — Réseau Kubernetes MédiSphère v1 (contrôle global)"
require_cmd kubectl jq yq curl ssh

_m15_e46_cfg="$(kube -n kube-system get cm cilium-config -o json 2>/dev/null)" || true
check_cmd "Cilium : remplacement de kube-proxy actif (kube-proxy-replacement=true)" \
  jq -e '.data["kube-proxy-replacement"] == "true"' <<<"$_m15_e46_cfg"
check_cmd "kube-proxy retiré (aucun DaemonSet kube-proxy)" \
  _m15x_jq '[.items[] | select(.metadata.name == "kube-proxy")] | length == 0' -n kube-system ds
check_cmd "Cilium : routage en tunnel VXLAN (choix de l'ADR-0150)" \
  jq -e '.data["routing-mode"] == "tunnel" and ((.data["tunnel-protocol"] // "vxlan") == "vxlan")' <<<"$_m15_e46_cfg"
check_cmd "Cilium : chiffrement WireGuard actif entre nœuds" \
  jq -e '.data["enable-wireguard"] == "true"' <<<"$_m15_e46_cfg"
check_cmd "Hubble : relay et UI disponibles" \
  _m15x_jq '[.items[] | select(.metadata.name == "hubble-relay" or .metadata.name == "hubble-ui") | select((.status.availableReplicas // 0) >= 1)] | length == 2' \
  -n kube-system deploy
check_cmd "Hubble UI publiée par la Gateway (route acceptée sur hubble.$_m15x_zone)" \
  _m15x_jq "[.items[] | select((.spec.hostnames // []) | index(\"hubble.$_m15x_zone\") != null)
    | select([.status.parents[]?.conditions[]? | select(.type == \"Accepted\" and .status == \"True\")] | length > 0)] | length > 0" httproutes -A
for _m15_e46_ns in mediagenda-dev mediagenda-recette; do
  check_cmd "$_m15_e46_ns : NetworkPolicy de refus par défaut (Ingress et Egress)" _m15x_refus_par_defaut "$_m15_e46_ns"
done
check_cmd "une CiliumClusterwideNetworkPolicy de base existe (M15-E28)" _m15x_jq '.items | length > 0' ccnp
check_cmd "ingress-nginx absent de k8s-par1 (projet retiré)" \
  _m15x_jq '[.items[] | select(.spec.controller == "k8s.io/ingress-nginx")] | length == 0' ingressclasses
check_cmd "publication externe : https://$_m15x_hote/sante répond 200 par la VIP des répartiteurs (10.10.70.200)" \
  bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 --resolve "$1:443:10.10.70.200" "https://$1/sante")" = 200 ]' _ "$_m15x_hote"
check_ssh "m15-essai (VMID 2151) détruite" "$WB_PVE_HOST" "! qm status 2151 >/dev/null 2>&1"
_m15_e46_pf="${WB_SRC:-$HOME/src}/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml"
check_cmd "bordure : flux vers 10.10.41.0/24 décrits dans group_vars/role_routeur/pare_feu.yml" grep -q '10\.10\.41\.' "$_m15_e46_pf"
check_cmd "bordure : flux RFC 2136 (VLAN 40 → autoritaire de dns01, 5300) décrit dans pare_feu.yml" grep -Eq 'RFC ?2136|dnsupdate|M15-E14' "$_m15_e46_pf"
check_cmd "documentation : ADR-0150" bash -c 'find "$1/docs/kubernetes" -name "ADR-0150*.md" 2>/dev/null | grep -q .' _ "$_m15x_depot"
for _m15_e46_rb in RB-150 RB-151 RB-152; do
  check_cmd "documentation : runbook $_m15_e46_rb" bash -c 'find "$1/docs/kubernetes" -name "$2*.md" 2>/dev/null | grep -q .' _ "$_m15x_depot" "$_m15_e46_rb"
done
check_cmd "documentation : matrice des flux du cluster commitée" _m15x_doc_commite docs/kubernetes/reseau/matrice-flux-cluster.md
check_cmd "documentation : architecture réseau du cluster commitée" _m15x_doc_commite docs/kubernetes/reseau/architecture.md
check_cmd "documentation : page de libre-service « publier une application » commitée" \
  _m15x_doc_commite docs/kubernetes/reseau/publier-une-application.md
check_cmd "plateforme/k8s : kubeadm ne réinstalle pas kube-proxy (proxy.disabled ou phase addon/kube-proxy sautée)" \
  bash -c 'f="$1"; [ -r "$f" ] || exit 1
    yq -e "select(.kind == \"ClusterConfiguration\") | .proxy.disabled == true" "$f" >/dev/null 2>&1 \
      || yq -e "select(.kind == \"InitConfiguration\") | .skipPhases[] | select(. == \"addon/kube-proxy\")" "$f" >/dev/null 2>&1' \
  _ "${WB_SRC:-$HOME/src}/k8s/cluster/kubeadm-config.yaml"
check_cmd "documentation : la matrice du socle cite le BGP des nœuds (179) et 10.10.41.0/24" \
  bash -c 'grep -q "10\.10\.41\." "$1/docs/socle/matrice-flux.md" && grep -q "179" "$1/docs/socle/matrice-flux.md"' _ "$_m15x_depot"
check_cmd "aucun secret TSIG en clair dans le dépôt de documentation" \
  bash -c '! grep -rEq "(secret|tsig)[^=:]*[=:][[:space:]]*\"?[A-Za-z0-9+/]{40,}={0,2}" "$1/docs" 2>/dev/null' _ "$_m15x_depot"
check_cmd "aucune panne M15 encore active" _m15x_aucune_panne_active
check_cmd "étiquette k8s-reseau-v1 posée sur plateforme/medisphere" gitlab_api "projects/plateforme%2Fmedisphere/repository/tags/k8s-reseau-v1"
