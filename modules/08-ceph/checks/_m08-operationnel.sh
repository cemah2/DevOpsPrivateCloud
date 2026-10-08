# shellcheck shell=bash
# _m08-operationnel.sh — fonctions partagées par les checks M08-E10 à M08-E23 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m08o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès au cluster : en SSH vers le nœud d'administration (WB_CEPH_ADMIN, défaut ceph01), avec
# « sudo -n ceph|rbd|radosgw-admin … » (ceph-common 20.2.3 du palier 1, clé client.admin du nœud
# _admin, jamais copiée) ; repli sur « sudo -n cephadm shell -- … » si l'outil manque sur l'hôte.
# Uniquement des commandes de LECTURE (ls, get, info, dump, status, stats) : les checks lisent
# une fois et réutilisent.

_M08O_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M08O_CLIENT="${WB_CEPH_CLIENT:-cephcli01}"
_M08O_CFG="$HOME/.config/workbook"
_M08O_TRAVAIL="$HOME/m08"
_M08O_PROJET_CEPH="projects/plateforme%2Fceph"
_M08O_PROJET_DOC="projects/plateforme%2Fmedisphere"
_M08O_REGISTRE="${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md"

# _m08o_outil OUTIL ARGS… — ceph, rbd ou radosgw-admin sur le nœud _admin ; sortie standard seule
# (vide si erreur). Repli cephadm : sudo n'a pas /usr/local/bin dans son PATH sous Rocky, le
# chemin de cephadm est cherché explicitement.
_m08o_outil() {
  local outil="$1"; shift
  remote "$_M08O_ADMIN" "if command -v $outil >/dev/null 2>&1; then sudo -n $outil $(printf '%q ' "$@"); else c=\$(command -v cephadm || ls /usr/sbin/cephadm /usr/local/sbin/cephadm /usr/local/bin/cephadm 2>/dev/null | head -n 1); sudo -n \"\$c\" shell -- $outil $(printf '%q ' "$@"); fi" 2>/dev/null || true
}
_m08o_ceph() { _m08o_outil ceph "$@"; }

# _m08o_client "commande" — commande sur cephcli01 (sortie, vide si erreur).
_m08o_client() { remote "$_M08O_CLIENT" "$1" 2>/dev/null || true; }

# _m08o_root600 HÔTE FICHIER — fichier présent, mode 600, propriétaire root (lu avec sudo).
_m08o_root600() {
  remote "$1" "sudo -n stat -c '%a %U' '$2'" 2>/dev/null | grep -qx '600 root'
}

# _m08o_local600 FICHIER — fichier local (adm01) non vide en mode 600.
_m08o_local600() { [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]; }

# _m08o_parent JSON_OSD_TREE NOM — nom du bucket parent de NOM dans « ceph osd tree -f json ».
_m08o_parent() {
  jq -r --arg n "$2" '. as $t | ([$t.nodes[] | select(.name == $n) | .id][0]) as $id
    | [$t.nodes[] | select((.children // []) | index($id)) | .name][0] // ""' <<<"$1" 2>/dev/null || true
}

# _m08o_pgs_propres JSON_STATUS — tous les PG sont active+clean (ceph status -f json).
_m08o_pgs_propres() {
  jq -e '.pgmap.num_pgs > 0 and ([.pgmap.pgs_by_state[] | select(.state_name != "active+clean")] | length == 0)' <<<"$1" >/dev/null 2>&1
}

# _m08o_fichier_main PROJET CHEMIN [REF] / _m08o_contenu_main — comme au module 06.
_m08o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}
_m08o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m08o_cert_tls HÔTE PORT — certificat présenté (texte d'openssl x509), vide si échec.
_m08o_cert_tls() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" -servername "$1" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || true
}

# _m08o_duree_jours TEXTE_X509 — durée de validité en jours (arrondie).
_m08o_duree_jours() {
  local debut fin
  debut="$(sed -n 's/^notBefore=//p' <<<"$1")"
  fin="$(sed -n 's/^notAfter=//p' <<<"$1")"
  [[ -n "$debut" && -n "$fin" ]] || { echo 9999; return 0; }
  echo $(( ($(date -d "$fin" +%s) - $(date -d "$debut" +%s) + 43200) / 86400 ))
}

# _m08o_registre MOTIF — le registre des secrets mentionne le motif (insensible à la casse).
_m08o_registre() { grep -qiE -- "$1" "$_M08O_REGISTRE" 2>/dev/null; }
