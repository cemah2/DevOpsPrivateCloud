# shellcheck shell=bash
# _m12-decouverte.sh — fonctions partagées par les checks M12-E02 à M12-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m12d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Hôtes (SSH en admin, noms courts résolus par le domaine de recherche de adm01, comme au M08) :
#   ctr01 (Docker), ctr02 et ctr03 (Podman, compte « app »), legacy01 (Legacy-RDV).
# Aucune fonction ne lance de conteneur : inspect, ps, port, exec de lecture seulement.

# shellcheck disable=SC2034  # constantes utilisées par les check-EXX.sh qui sourcent ce fichier
_M12D_SRC="${WB_SRC:-$HOME/src}"
_M12D_DNS="10.10.20.10"
_M12D_DOMAINE="par1.medisphere.internal"
_M12D_APP="app"
_M12D_APP_UID="1001"
_M12D_SUBID_DEBUT=524288
_M12D_SUBID_NOMBRE=65536

# _m12d_fqdn HOTE — nom complet (ctr01 → ctr01.par1.medisphere.internal).
_m12d_fqdn() {
  printf '%s.%s' "$1" "$_M12D_DOMAINE"
}

# _m12d_ssh HOTE "COMMANDE" — commande distante en admin ; sortie sur stdout, jamais d'échec.
_m12d_ssh() {
  remote "$1" "$2" 2>/dev/null || true
}

# _m12d_docker "ARGUMENTS" — commande docker sur ctr01 (admin est dans le groupe docker).
_m12d_docker() {
  remote ctr01 "docker $1" 2>/dev/null || true
}

# _m12d_podman HOTE "ARGUMENTS" — commande podman EN TANT QUE app, avec sa session systemd
# (linger) : XDG_RUNTIME_DIR et bus D-Bus de /run/user/<UID>. Lecture seule.
_m12d_podman() {
  remote "$1" "cd /tmp && sudo -n -u $_M12D_APP env XDG_RUNTIME_DIR=/run/user/$_M12D_APP_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_M12D_APP_UID/bus podman $2" 2>/dev/null || true
}

# _m12d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m12d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m12d_correspond TEXTE REGEX — le texte correspond à la regex étendue (grep -E).
_m12d_correspond() {
  [[ -n "$1" ]] && grep -Eq -- "$2" <<<"$1"
}

# _m12d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m12d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m12d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m12d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m12d_dans_pool VMID — la VM est membre du pool lab.
_m12d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m12d_projet PROJET — chemin GitLab encodé (mediagenda/api → mediagenda%2Fapi).
_m12d_projet() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m12d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m12d_fichier_main() {
  local projet chemin
  projet="$(_m12d_projet "$1")"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m12d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m12d_contenu_main() {
  local projet chemin
  projet="$(_m12d_projet "$1")"
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m12d_arbre_main PROJET [DOSSIER] — chemins des fichiers de main (récursif, 100 premiers).
_m12d_arbre_main() {
  local projet chemin=""
  projet="$(_m12d_projet "$1")"
  [[ -n "${2:-}" ]] && chemin="&path=$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$projet/repository/tree?ref=main&recursive=true&per_page=100$chemin" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m12d_http URL — corps de la réponse HTTP (vide si pas de réponse), sans suivre de redirection.
_m12d_http() {
  curl -s --max-time "${WB_TIMEOUT:-5}" "$1" 2>/dev/null || true
}

# _m12d_inspect CONTENEUR FORMAT — docker inspect --format sur ctr01 (vide si absent).
_m12d_inspect() {
  _m12d_docker "inspect --format '$2' $1"
}
