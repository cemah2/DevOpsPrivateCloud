# shellcheck shell=bash
# _m14-decouverte.sh — fonctions partagées par les checks M14-E02 à M14-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m14d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès au cluster :
#   - à partir de M14-E06 : « kube » (check-lib.sh), compte de service wb-checks en lecture ;
#   - AVANT M14-E06 (E04, E05) : si le kubeconfig des checks n'existe pas encore, repli en SSH sur
#     le premier nœud de contrôle, « sudo -n kubectl --kubeconfig /etc/kubernetes/admin.conf »,
#     commandes d'OBSERVATION seulement (get). Le repli est signalé à l'écran.
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_K8S_KUBECONFIG  kubeconfig des checks (~/.config/workbook/k8s-checks.kubeconfig)
#   WB_K8S_CP          nœuds de contrôle (k8s-cp01 k8s-cp02 k8s-cp03)
#   WB_K8S_WORKERS     travailleurs (k8s-w01 k8s-w02 k8s-w03)
#   WB_STORAGE_NVME    stockage Proxmox des disques système (local-nvme)

_M14D_KCFG="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
read -r -a _M14D_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M14D_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M14D_REF="${_M14D_CP[0]}"
_M14D_NVME="${WB_STORAGE_NVME:-local-nvme}"
_M14D_DNS="10.10.20.10"
_M14D_VIP="10.10.40.200"
_M14D_API="k8s-api.par1.medisphere.internal"
# Version de référence : 1.35.9 au palier 1 ; après la montée de version (M14-E25), celle que le
# cluster déclare (ConfigMap kubeadm-config), pour que ces checks restent rejouables jusqu'à M14-E46.
# Voir _m14d_version_cluster plus bas ; WB_M14_K8S_VERSION la force si besoin.
_M14D_VERSION="1.35.9"
_M14D_PAUSE="registry.k8s.io/pause:3.10.1"
_M14D_ETCD="3.6.6"
_M14D_REPLI_SIGNALE=0

# Table du plan : nom → « VMID adresse rôle ».
declare -A _M14D_PLAN=(
  [k8s-cp01]="2141 10.10.40.51 cp" [k8s-cp02]="2142 10.10.40.52 cp" [k8s-cp03]="2143 10.10.40.53 cp"
  [k8s-w01]="2144 10.10.40.61 w" [k8s-w02]="2145 10.10.40.62 w" [k8s-w03]="2146 10.10.40.63 w"
)

# _m14d_k ARGS… — kubectl en lecture (sortie sur stdout). Voir l'en-tête pour le repli SSH.
_m14d_k() {
  if [[ -r "$_M14D_KCFG" ]]; then
    kube "$@" 2>/dev/null || true
    return 0
  fi
  if (( _M14D_REPLI_SIGNALE == 0 )); then
    printf '  [..]   kubeconfig des checks absent (M14-E06) : lecture par SSH sur %s (admin.conf, get seulement)\n' "$_M14D_REF" >&2
    _M14D_REPLI_SIGNALE=1
  fi
  local args
  printf -v args '%q ' "$@"
  remote "$_M14D_REF" "sudo -n kubectl --kubeconfig /etc/kubernetes/admin.conf --request-timeout=${WB_TIMEOUT:-5}s $args" 2>/dev/null || true
}

# _m14d_version_cluster — version déclarée par le cluster (kubernetesVersion de kubeadm-config, sans
# le « v ») ; vide si le cluster n'existe pas encore ou ne répond pas.
_m14d_version_cluster() {
  _m14d_k -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' |
    sed -n 's/^kubernetesVersion: *v\{0,1\}\([0-9][0-9.]*\)$/\1/p' | head -n 1
}
_M14D_REPLI_SIGNALE=1   # pas de message de repli pour cette détection silencieuse
_M14D_VERSION="${WB_M14_K8S_VERSION:-$(_m14d_version_cluster)}"
_M14D_VERSION="${_M14D_VERSION:-1.35.9}"
_M14D_MINEURE="${_M14D_VERSION%.*}"
# Images de kubeadm par mineure (kubeadm config images list) : 1.35 → pause 3.10.1, etcd 3.6.6 ;
# 1.36 → pause 3.10.2, etcd 3.6.8. Une autre mineure : à vérifier sur ta version.
case "$_M14D_MINEURE" in
  1.35) _M14D_PAUSE="registry.k8s.io/pause:3.10.1"; _M14D_ETCD="3.6.6" ;;
  *) _M14D_PAUSE="registry.k8s.io/pause:3.10.2"; _M14D_ETCD="3.6.8" ;;
esac
# Version d'etcd réellement déployée (image du pod statique), si l'API la donne.
_m14d_etcd_cluster="$(_m14d_k -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].spec.containers[0].image}' |
  sed -n 's|.*/etcd:\([0-9][0-9.]*\)-[0-9]*$|\1|p')"
_M14D_ETCD="${_m14d_etcd_cluster:-$_M14D_ETCD}"
_M14D_REPLI_SIGNALE=0

# _m14d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m14d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m14d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m14d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m14d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m14d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m14d_dans_pool VMID — la VM est membre du pool lab.
_m14d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m14d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m14d_fichier_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m14d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m14d_contenu_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m14d_arbre_main PROJET — chemins de tous les fichiers de main (un par ligne, 3 pages de 100).
_m14d_arbre_main() {
  local projet page
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  for page in 1 2 3; do
    gitlab_api "projects/$projet/repository/tree?ref=main&recursive=true&per_page=100&page=$page" 2>/dev/null \
      | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
  done
}

# _m14d_porteur_vip — nœud de contrôle qui porte la VIP (vide si aucun, plusieurs noms si plusieurs).
_m14d_porteur_vip() {
  local n
  for n in "${_M14D_CP[@]}"; do
    if remote "$n" "ip -o -4 addr show | grep -q ' ${_M14D_VIP}/'" >/dev/null 2>&1; then
      printf '%s ' "$n"
    fi
  done
}

# _m14d_haproxy_stat HÔTE — CSV « show stat » d'HAProxy (socket d'administration, sudo -n).
_m14d_haproxy_stat() {
  remote "$1" "echo 'show stat' | sudo -n socat stdio unix-connect:/run/haproxy/admin.sock" 2>/dev/null || true
}

# _m14d_proxy_get ESPACE SERVICE:PORT CHEMIN — GET à travers le mandataire de l'API (services/proxy).
_m14d_proxy_get() {
  _m14d_k get --raw "/api/v1/namespaces/$1/services/$2/proxy$3"
}
