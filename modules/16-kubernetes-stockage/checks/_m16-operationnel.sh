# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m16-operationnel.sh — fonctions partagées par les checks M16-E10 à M16-E23 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m16o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès utilisés (tous en lecture) :
#   kube (check-lib) : compte de service wb-checks (WB_K8S_KUBECONFIG), complété par le
#     ClusterRole wb-checks-stockage (M16-E10) — ne lit JAMAIS les Secrets
#   remote <travailleur> : état des disques et montages (SSH admin, sudo -n en lecture)
#   gitlab_api : GET ; fichiers locaux de adm01 (~/m16/, ~/.config/workbook/, dépôt de doc)
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) : WB_K8S_WORKERS, WB_DEPOT.

_M16O_TRAVAILLEURS="${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M16O_TRAVAIL="$HOME/m16"
_M16O_CFG="$HOME/.config/workbook"
_M16O_REGISTRE="${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md"
_M16O_PROJET_K8S="plateforme/k8s"
_M16O_PROJET_DOC="plateforme/medisphere"
_M16O_DISQUE="/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK"
_M16O_32GIO=34359738368

# _m16o_kj ARGS… — sortie JSON de « kube … -o json » (vide si erreur ou objet absent).
_m16o_kj() { kube "$@" -o json 2>/dev/null || true; }

# _m16o_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m16o_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m16o_absent ARGS… — OK si « kube get ARGS » ne renvoie aucun objet (et que l'API répond).
_m16o_absent() {
  local sortie
  sortie="$(kube get "$@" --ignore-not-found -o name 2>&1)" || return 1
  [[ -z "$sortie" ]]
}

# _m16o_api_repond — l'API répond au compte des vérifications.
_m16o_api_repond() { kube get --raw /version >/dev/null 2>&1; }

# _m16o_peut VERBE RESSOURCE [ESPACE] — réponse de « auth can-i » pour wb-checks (yes/no).
_m16o_peut() {
  if [[ -n "${3:-}" ]]; then kube auth can-i "$1" "$2" -n "$3" 2>/dev/null || true
  else kube auth can-i "$1" "$2" -A 2>/dev/null || true; fi
}

# Filtre jq : quantité Kubernetes (« 2Gi », « 500M », « 1073741824 ») → octets.
# shellcheck disable=SC2016  # texte jq
_M16O_JQ_OCTETS='def octets: tostring | capture("^(?<n>[0-9.]+)(?<u>[KMGTPE]i?)?$") as $q
  | ($q.n | tonumber) * ({"": 1, "Ki": 1024, "Mi": 1048576, "Gi": 1073741824, "Ti": 1099511627776,
     "K": 1000, "M": 1000000, "G": 1000000000, "T": 1000000000000}[$q.u // ""]);'

# _m16o_defaut_unique — la seule classe par défaut du cluster est ceph-rbd.
_m16o_defaut_unique() {
  _m16o_json "$(_m16o_kj get storageclass)" '
    [.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true")
     | .metadata.name] == ["ceph-rbd"]'
}

# _m16o_journal EXX [LIGNES] — ~/m16/eXX/journal.md existe avec au moins LIGNES lignes non vides.
_m16o_journal() {
  local f="$_M16O_TRAVAIL/${1,,}/journal.md" min="${2:-10}"
  [[ -s "$f" ]] && (( $(grep -cv '^[[:space:]]*$' "$f" 2>/dev/null || echo 0) >= min ))
}

# _m16o_journal_mentionne EXX REGEX — le journal contient REGEX (grep -E, insensible à la casse).
_m16o_journal_mentionne() { grep -qiE -- "$2" "$_M16O_TRAVAIL/${1,,}/journal.md" 2>/dev/null; }

# _m16o_fichier_main PROJET CHEMIN — le fichier existe sur main du projet GitLab.
_m16o_fichier_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m16o_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m16o_contenu_main() {
  local projet chemin
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m16o_dossier_absent_main PROJET CHEMIN — aucun fichier sous CHEMIN sur main.
_m16o_dossier_absent_main() {
  local projet chemin sortie
  projet="$(jq -rn --arg v "$1" '$v | @uri')"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  sortie="$(gitlab_api "projects/$projet/repository/tree?ref=main&path=$chemin" 2>/dev/null)" || return 0
  [[ "$(jq 'length' <<<"$sortie" 2>/dev/null || echo 1)" == 0 ]]
}

# _m16o_sans_cle TEXTE — aucun motif de clé (S3, cephx, mot de passe) dans le texte.
_m16o_sans_cle() {
  ! grep -qE -- '(aws_secret_access_key|ACCESS_SECRET_KEY|secretKey|userKey|repository-password|password)[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9/+=]{16,}|AQ[A-Za-z0-9+/]{38}==' <<<"$1"
}

# _m16o_local600 FICHIER — fichier local (adm01) non vide en mode 600.
_m16o_local600() { [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]; }

# _m16o_registre MOTIF — le registre des secrets mentionne le motif (insensible à la casse).
_m16o_registre() { grep -qiE -- "$1" "$_M16O_REGISTRE" 2>/dev/null; }

# _m16o_sur_travailleurs "COMMANDE" — OK si la commande distante réussit sur chaque travailleur ;
# %N dans la commande est remplacé par le nom court du nœud.
_m16o_sur_travailleurs() {
  local n
  for n in $_M16O_TRAVAILLEURS; do
    remote "$n" "${1//%N/$n}" >/dev/null 2>&1 || return 1
  done
}

# _m16o_disque_32g NOM_SUFFIXE — le disque <nœud>-SUFFIXE existe sur chaque travailleur (32 Gio).
_m16o_disque_32g() {
  _m16o_sur_travailleurs "[ \"\$(lsblk -bdno SIZE $_M16O_DISQUE""_%N-$1 2>/dev/null)\" = $_M16O_32GIO ]"
}

# _m16o_disque_vierge NOM_SUFFIXE — le disque n'a aucune signature (wipefs) sur chaque travailleur.
_m16o_disque_vierge() {
  _m16o_sur_travailleurs "d=$_M16O_DISQUE""_%N-$1; [ -b \"\$d\" ] && [ -z \"\$(sudo -n wipefs -n \"\$d\" 2>/dev/null)\" ] && [ -z \"\$(lsblk -no FSTYPE \"\$d\" | tr -d '[:space:]')\" ]"
}

# _m16o_ready_cnpg ESPACE CLUSTER N — le Cluster CNPG a au moins N instances prêtes, état sain.
_m16o_ready_cnpg() {
  _m16o_json "$(_m16o_kj get clusters.postgresql.cnpg.io "$2" -n "$1")" '
    (.status.readyInstances // 0) >= $n and (.status.phase // "") == "Cluster in healthy state"' --argjson n "$3"
}

# _m16o_journal_tout EXX MIN REGEX… — journal d'au moins MIN lignes non vides contenant chaque REGEX.
_m16o_journal_tout() {
  local ex="$1" min="$2" r
  shift 2
  _m16o_journal "$ex" "$min" || return 1
  for r in "$@"; do _m16o_journal_mentionne "$ex" "$r" || return 1; done
}
