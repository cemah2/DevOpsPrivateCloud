# shellcheck shell=bash
# _m14-production.sh — fonctions partagées par les checks M14-E24 à M14-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_K8S_KUBECONFIG (via kube), WB_K8S_CP, WB_K8S_WORKERS,
# WB_PVE_HOST, WB_PBS_HOST, WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE, WB_S3_ENDPOINT, WB_TIMEOUT.
# Accès : « kube » (compte de service wb-checks, lecture, pas les Secrets) ; SSH vers les nœuds avec
# « sudo -n » pour des LECTURES seulement (stat, cat d'un état, etcdctl get/status/list, openssl) ;
# aucune valeur de Secret n'est jamais affichée ni conservée (seuls des préfixes de quelques octets).

read -r -a _M14P_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M14P_TRAV <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M14P_TOUS=("${_M14P_CP[@]}" "${_M14P_TRAV[@]}")
_M14P_ZONE=par1.medisphere.internal
_M14P_VIP=k8s-api.par1.medisphere.internal
_M14P_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M14P_S3_ENV="$HOME/.config/workbook/s3-etcd.env"
_M14P_COMPARTIMENT=etcd-k8s-par1
declare -A _M14P_IP=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53
  [k8s-w01]=10.10.40.61 [k8s-w02]=10.10.40.62 [k8s-w03]=10.10.40.63)

# --- API Kubernetes (compte wb-checks) ---------------------------------------------------------

# _m14p_json ARGS… — sortie JSON valide de « kube ARGS -o json », ou « null ».
_m14p_json() {
  local s
  s="$(kube "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m14p_jq JSON FILTRE — filtre booléen jq sur un document (null → faux).
_m14p_jq() { [[ "$1" != null ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

_m14p_joignable() { [[ "$(kube get --raw /readyz 2>/dev/null)" == ok ]]; }

# _m14p_cc — ClusterConfiguration en vigueur (ConfigMap kube-system/kubeadm-config), texte YAML.
_m14p_cc() { kube -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null; }

# _m14p_pod_statique COMPOSANT NŒUD — JSON du pod statique (miroir) COMPOSANT-NŒUD, ou null.
_m14p_pod_statique() { _m14p_json -n kube-system get pod "$1-$2"; }

# _m14p_arg_api NŒUD NOM REGEX — le serveur d'API du nœud tourne avec --NOM=VALEUR, VALEUR ~ REGEX.
_m14p_arg_api() {
  local p
  p="$(_m14p_pod_statique kube-apiserver "$1")"
  _m14p_jq "$p" "any(.spec.containers[0].command[]; test(\"^--$2=($3)\$\"))"
}

# _m14p_pod_pret JSON — le pod est Running et Ready.
_m14p_pod_pret() {
  _m14p_jq "$1" '.status.phase == "Running" and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
}

# --- Nœuds (SSH, sudo -n, lecture) ----------------------------------------------------------------

_m14p_sudo() { remote "$1" "sudo -n $2" 2>/dev/null; }

# _m14p_etcdctl NŒUD ARGS — etcdctl du nœud (rôle etcd_instantane) vers son membre local.
_m14p_etcdctl() {
  remote "$1" "sudo -n env ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key \
ETCDCTL_DIAL_TIMEOUT=5s /usr/local/bin/etcdctl $2" 2>/dev/null
}

# _m14p_etcd_json NŒUD ARGS — sortie JSON d'etcdctl (-w json), ou null.
_m14p_etcd_json() {
  local s
  s="$(_m14p_etcdctl "$1" "$2 -w json")" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m14p_prefixe_secret NŒUD ESPACE NOM — les 40 premiers octets (imprimables) de la valeur stockée.
_m14p_prefixe_secret() {
  _m14p_etcdctl "$1" "get /registry/secrets/$2/$3 --print-value-only" | head -c 40 | tr -c '[:print:]' '.' || true
}

# _m14p_version_etcd_cluster — version de l'image etcd du pod statique du premier nœud de contrôle
# (ex. 3.6.8), ou vide.
_m14p_version_etcd_cluster() {
  _m14p_pod_statique etcd "${_M14P_CP[0]}" | jq -r '.spec.containers[0].image // empty' 2>/dev/null \
    | sed -nE 's/.*:v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p'
}

# _m14p_age_succes NŒUD — secondes depuis le dernier succès de l'instantané etcd du nœud (ou vide).
_m14p_age_succes() {
  local t
  t="$(_m14p_sudo "$1" 'cat /var/lib/etcd-instantane/dernier-succes' | cut -d' ' -f1)" || t=""
  [[ "$t" =~ ^[0-9]+$ ]] && echo $(( $(date +%s) - t ))
}

# --- Stockage objet (identité etcd-k8s, lecture) ---------------------------------------------------

_m14p_s3() {
  [[ -r "$_M14P_S3_ENV" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M14P_S3_ENV"
    set +a
    exec aws --endpoint-url "$_M14P_S3" --output json "$@" </dev/null
  )
}

# --- GitLab (jeton des checks, lecture) -------------------------------------------------------------

# _m14p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m14p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m14p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif.
_m14p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m14p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m14p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m14p_arbre() {
  local p="${1//\//%2F}" d="${2//\//%2F}"
  gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -r '.[]? | select(.type == "blob") | .path'
}

# _m14p_doc_prefixe DOSSIER PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous DOSSIER de plateforme/medisphere
# (main) contient chaque motif.
_m14p_doc_prefixe() {
  local d="$1" pre="$2" f
  shift 2
  f="$(_m14p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -1)" || f=""
  [[ -n "$f" ]] || return 1
  _m14p_fichier_contient plateforme/medisphere "$f" "$@"
}

# --- PBS -------------------------------------------------------------------------------------------------

# _m14p_pbs_vm_recente VMID HEURES — une sauvegarde de la VM de moins de HEURES heures dans l'espace
# de noms par1/k8s du datastore ds-lab (lecture du datastore en root sur pbs01).
_m14p_pbs_vm_recente() {
  remote "$WB_PBS_HOST" "
    p=\$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE 's/.*\"path\" *: *\"([^\"]+)\".*/\1/p')
    [ -n \"\$p\" ] || exit 1
    find \"\$p/ns/par1/ns/k8s/vm/$1\" -mindepth 1 -maxdepth 1 -type d -mmin -$(($2 * 60)) 2>/dev/null | grep -q ." \
    >/dev/null 2>&1
}

# --- Certificats -----------------------------------------------------------------------------------------

# _m14p_ca_cluster FICHIER — écrit la CA du cluster (kubeconfig des checks) dans FICHIER.
_m14p_ca_cluster() {
  local f="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
  kubectl --kubeconfig "$f" config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
    2>/dev/null | base64 -d >"$1" 2>/dev/null
  [[ -s "$1" ]]
}

# _m14p_fin_servie HÔTE PORT — date de fin (secondes) du certificat présenté sur HÔTE:PORT, ou vide.
_m14p_fin_servie() {
  local d
  d="$(timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)" || d=""
  [[ -n "$d" ]] && date -d "$d" +%s
}
