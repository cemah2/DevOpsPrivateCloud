# shellcheck shell=bash
# _m16-decouverte.sh — fonctions partagées par les checks M16-E02 à M16-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m16d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès utilisés (tous en lecture) :
#   kube (check-lib) : compte de service wb-checks (WB_K8S_KUBECONFIG) — ne lit PAS les Secrets
#   remote "$WB_CEPH_ADMIN" : commandes « ceph » et « rbd » d'observation (sudo -n), M08
#   remote <travailleur> : état réseau, montages, fichiers (SSH admin, sudo -n en lecture)
#   remote "$WB_PVE_HOST" : qm config ; gitlab_api, netbox_api : GET
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_CEPH_ADMIN (ceph01), WB_K8S_WORKERS (« k8s-w01 k8s-w02 k8s-w03 »), WB_K8S_CP, WB_SRC

_M16D_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M16D_TRAVAILLEURS="${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M16D_CP="${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
_M16D_SRC="${WB_SRC:-$HOME/src}"
_M16D_ETIQUETTE="medisphere.internal/stockage-ceph"
_M16D_MONS="10.10.30.51 10.10.30.52 10.10.30.53"
_M16D_CSI_VERSION="v3.18.1"
_M16D_SNAP_VERSION="v8.6.0"
_M16D_FEATURES="layering,exclusive-lock,object-map,fast-diff,deep-flatten"

# _m16d_kj ARGS… — sortie JSON de « kube … -o json » (vide si erreur).
_m16d_kj() {
  kube "$@" -o json 2>/dev/null || true
}

# _m16d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m16d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m16d_ceph "ARGUMENTS" — commande « ceph » d'observation sur le nœud _admin (stdout).
_m16d_ceph() {
  remote "$_M16D_ADMIN" "if command -v ceph >/dev/null; then sudo -n ceph $1; else sudo -n cephadm shell -- ceph $1; fi" 2>/dev/null || true
}

# _m16d_rbd "ARGUMENTS" — commande « rbd » d'observation sur le nœud _admin (stdout).
_m16d_rbd() {
  remote "$_M16D_ADMIN" "if command -v rbd >/dev/null; then sudo -n rbd $1; else sudo -n cephadm shell -- rbd $1; fi" 2>/dev/null || true
}

# _m16d_fsid — fsid de ceph-par1 (vide si le cluster ne répond pas).
_m16d_fsid() {
  _m16d_ceph "fsid" | tr -d '[:space:]'
}

# _m16d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m16d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m16d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m16d_fichier_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m16d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m16d_contenu_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m16d_recherche_main PROJET MOT — OK si la recherche de code du projet trouve MOT sur main.
_m16d_recherche_main() {
  local projet mot
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  mot="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/search?scope=blobs&ref=main&search=$mot" 2>/dev/null \
    | jq -e 'length > 0' >/dev/null 2>&1
}

# _m16d_pods_prets ESPACE SELECTEUR — nombre de pods prêts (condition Ready) pour le sélecteur.
_m16d_pods_prets() {
  _m16d_kj get pods -n "$1" -l "$2" \
    | jq '[.items[] | select(.status.conditions // [] | any(.type == "Ready" and .status == "True"))] | length' 2>/dev/null \
    || echo 0
}

# _m16d_noeuds_pods ESPACE SELECTEUR — noms des nœuds des pods (triés, uniques, un par ligne).
_m16d_noeuds_pods() {
  _m16d_kj get pods -n "$1" -l "$2" | jq -r '[.items[].spec.nodeName // empty] | unique[]' 2>/dev/null || true
}

# _m16d_travailleurs_tries — les travailleurs attendus, triés, un par ligne.
_m16d_travailleurs_tries() {
  tr ' ' '\n' <<<"$_M16D_TRAVAILLEURS" | sed '/^$/d' | sort
}

# _m16d_sc NOM — la StorageClass en JSON (vide si absente).
_m16d_sc() {
  _m16d_kj get storageclass "$1"
}

# _m16d_absent ARGS… — OK si l'API répond « NotFound » pour « kube get ARGS… ». Un échec d'accès
# (kubeconfig illisible, API injoignable) n'est PAS une absence : le contrôle reste rouge.
_m16d_absent() {
  local sortie
  sortie="$(kube get "$@" 2>&1)" || true
  grep -q '(NotFound)' <<<"$sortie"
}

# _m16d_netbox_ip ADRESSE — (sans masque : le filtre « address » de NetBox l'accepte) l'adresse existe une fois dans NetBox et est affectée à une interface.
_m16d_netbox_ip() {
  netbox_api "ipam/ip-addresses/?address=$1" 2>/dev/null \
    | jq -e '.count == 1 and .results[0].assigned_object_id != null' >/dev/null 2>&1
}
