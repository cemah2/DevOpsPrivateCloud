# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes, développés plus tard
# _m18-decouverte.sh — fonctions partagées par les checks du module 18, paliers 1 et 2 (lecture seule).
# Sourcé par les check-EXX.sh (lab/bin/check ne lance que les check-EXX.sh). Préfixe _m18d_.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès aux clusters d'essai : leurs kubeconfigs d'ADMINISTRATION (~/.config/workbook/m18/*.kubeconfig),
# en commandes « get » seulement (ces clusters sont jetables et n'ont pas de compte wb-checks) ;
# Talos : talosconfig du même dossier, commandes « get », « version », « list » seulement.
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M18_DIR    dossier des fichiers d'accès (~/.config/workbook/m18)
#   WB_M18_DEV    poste de développement (m18-dev01)
#   WB_M18_K3S    nœud k3s de l'agence (k3s01)
#   WB_M18_RKE2   nœuds RKE2 (rke2-01 rke2-02 rke2-03)
#   WB_M18_TALOS  adresses des nœuds Talos (10.10.99.85 10.10.99.86 10.10.99.87)

_M18D_DIR="${WB_M18_DIR:-$HOME/.config/workbook/m18}"
_M18D_DEV="${WB_M18_DEV:-m18-dev01}"
_M18D_K3S="${WB_M18_K3S:-k3s01}"
read -r -a _M18D_RKE2 <<<"${WB_M18_RKE2:-rke2-01 rke2-02 rke2-03}"
read -r -a _M18D_TALOS <<<"${WB_M18_TALOS:-10.10.99.85 10.10.99.86 10.10.99.87}"
_M18D_DOMAINE="par1.medisphere.internal"
_M18D_SCHEMA="ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
_M18D_KIND_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"

# _m18d_k CLUSTER ARGS… — kubectl en lecture avec ~/.config/workbook/m18/<CLUSTER>.kubeconfig.
_m18d_k() {
  local f="$_M18D_DIR/$1.kubeconfig"
  shift
  [[ -r "$f" ]] || { echo "kubeconfig illisible : $f" >&2; return 1; }
  kubectl --kubeconfig "$f" --request-timeout="${WB_TIMEOUT:-5}s" "$@" 2>/dev/null
}

# _m18d_kj CLUSTER ARGS… — comme _m18d_k, sortie vide en cas d'échec (pour les filtres jq).
_m18d_kj() { _m18d_k "$@" || true; }

# _m18d_talos ARGS… — talosctl avec le talosconfig du module (lecture seule par convention).
_m18d_talos() {
  local f="$_M18D_DIR/talosconfig"
  [[ -r "$f" ]] || { echo "talosconfig illisible : $f" >&2; return 1; }
  timeout 20 talosctl --talosconfig "$f" "$@" 2>/dev/null
}

# _m18d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m18d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m18d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m18d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m18d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m18d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m18d_dans_pool VMID — la VM est membre du pool lab.
_m18d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m18d_vm DESCRIPTION VMID NOM COEURS MEMOIRE MAC ETIQ… — contrôles Proxmox communs d'une VM.
_m18d_vm() {
  local desc="$1" vmid="$2" nom="$3" coeurs="$4" memoire="$5" mac="$6" conf
  shift 6
  conf="$(_m18d_qm "$vmid")"
  check_cmd "$desc : VM $vmid « $nom », $coeurs vCPU, $memoire Mio" bash -c \
    'grep -qx "name: $2" <<<"$1" && grep -qx "cores: $3" <<<"$1" && grep -qx "memory: $4" <<<"$1"' \
    _ "$conf" "$nom" "$coeurs" "$memoire"
  check_cmd "$desc : carte sur vsandbox, MAC $mac" bash -c \
    'grep -Eiq "^net0: virtio=$2,.*bridge=vsandbox" <<<"$1"' _ "$conf" "$mac"
  local ok=0
  if _m18d_etiquettes "$conf" "$@" && _m18d_dans_pool "$vmid"; then ok=1; fi
  check_cmd "$desc : étiquettes $*, pool lab" test "$ok" = 1
}

# _m18d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m18d_fichier_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m18d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m18d_contenu_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m18d_arbre_main PROJET — chemins de tous les fichiers de main (un par ligne, 5 pages de 100).
_m18d_arbre_main() {
  local projet page
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  for page in 1 2 3 4 5; do
    gitlab_api "projects/$projet/repository/tree?ref=main&recursive=true&per_page=100&page=$page" 2>/dev/null \
      | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
  done
}

# _m18d_fichiers_main PROJET CHEMIN… — un contrôle par fichier attendu sur main.
_m18d_fichiers_main() {
  local projet="$1" f
  shift
  for f in "$@"; do
    check_cmd "$projet (main) : $f" _m18d_fichier_main "$projet" "$f"
  done
}

# _m18d_600 FICHIER — le fichier existe et est en 600.
_m18d_600() {
  [[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]
}

# _m18d_serveur CLUSTER — URL du serveur écrite dans le kubeconfig du cluster.
_m18d_serveur() {
  kubectl --kubeconfig "$_M18D_DIR/$1.kubeconfig" config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true
}

# _m18d_noeuds_prets JSON NOMBRE VERSION — exactement NOMBRE nœuds, tous Ready, kubelet VERSION.
_m18d_noeuds_prets() {
  _m18d_json "$1" '(.items | length == $n) and all(.items[];
      ([.status.conditions[] | select(.type == "Ready")][0].status == "True")
      and .status.nodeInfo.kubeletVersion == $v)' --argjson n "$2" --arg v "$3"
}

# _m18d_port_ferme HÔTE PORT — aucune connexion TCP n'aboutit.
_m18d_port_ferme() {
  ! timeout "${WB_TIMEOUT:-5}" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}
