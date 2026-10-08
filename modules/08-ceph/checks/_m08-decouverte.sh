# shellcheck shell=bash
# _m08-decouverte.sh — fonctions partagées par les checks M08-E02 à M08-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m08d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_CEPH_ADMIN   nœud _admin où lancer « ceph » (sudo -n) : ceph01
#   WB_CEPH_CLIENT  client de test : cephcli01
#   WB_STORAGE_SSD, WB_STORAGE_BULK, WB_STORAGE_NVME : noms des stockages Proxmox (M00)

_M08D_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M08D_CLIENT="${WB_CEPH_CLIENT:-cephcli01}"
_M08D_SSD="${WB_STORAGE_SSD:-ssd-lab}"
_M08D_BULK="${WB_STORAGE_BULK:-hdd-bulk}"
_M08D_NVME="${WB_STORAGE_NVME:-local-nvme}"
_M08D_SRC="${WB_SRC:-$HOME/src}"
_M08D_DNS="10.10.20.10"
_M08D_VERSION="20.2.3"

# _m08d_ceph "ARGUMENTS" — commande « ceph » sur le nœud _admin (sortie sur stdout).
# Repli sur « cephadm shell » si ceph-common manque (plus lent : un conteneur par appel).
_m08d_ceph() {
  remote "$_M08D_ADMIN" "if command -v ceph >/dev/null; then sudo -n ceph $1; else sudo -n cephadm shell -- ceph $1; fi" 2>/dev/null || true
}

# _m08d_rbd "ARGUMENTS" — commande « rbd » sur le nœud _admin.
_m08d_rbd() {
  remote "$_M08D_ADMIN" "if command -v rbd >/dev/null; then sudo -n rbd $1; else sudo -n cephadm shell -- rbd $1; fi" 2>/dev/null || true
}

# _m08d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m08d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m08d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m08d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m08d_qm_a CONFIG REGEX — une ligne de la configuration correspond à la regex étendue.
_m08d_qm_a() {
  grep -Eq -- "$2" <<<"$1"
}

# _m08d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m08d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m08d_dans_pool VMID — la VM est membre du pool lab.
_m08d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m08d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab
# (PROJET sous la forme « plateforme/ceph »).
_m08d_fichier_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m08d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m08d_contenu_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m08d_sante — statut de santé (HEALTH_OK, HEALTH_WARN, HEALTH_ERR ou vide).
_m08d_sante() {
  _m08d_ceph "health -f json" | jq -r '.status // empty' 2>/dev/null || true
}

# _m08d_alertes — codes des alertes de santé en cours, séparés par des espaces.
_m08d_alertes() {
  _m08d_ceph "health -f json" | jq -r '(.checks // {}) | keys | join(" ")' 2>/dev/null || true
}

# _m08d_disque CONFIG DISQUE STOCKAGE TAILLE SSD(0|1) — le disque (scsiN) est sur ce stockage,
# de cette taille, exclu des sauvegardes, et présenté SSD (1) ou rotatif (0).
_m08d_disque() {
  local ligne
  ligne="$(grep -E "^$2: " <<<"$1")" || return 1
  [[ "$ligne" =~ ^$2:\ $3: ]] || return 1
  [[ "$ligne" =~ (,|\ )size=$4(,|$) ]] || return 1
  [[ "$ligne" =~ ,backup=0(,|$) ]] || return 1
  if [[ "$5" == 1 ]]; then
    [[ "$ligne" =~ ,ssd=1(,|$) ]]
  else
    ! [[ "$ligne" =~ ,ssd=1(,|$) ]]
  fi
}
