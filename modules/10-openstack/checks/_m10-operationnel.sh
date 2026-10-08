# shellcheck shell=bash
# _m10-operationnel.sh — fonctions partagées par les checks M10-E10 à M10-E23 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m10o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès utilisés (tous en lecture) :
#   - API OpenStack : client « openstack » de adm01, cloud $WB_OS_CLOUD (défaut medisphere-admin)
#     de ~/.config/openstack/clouds.yaml ; certains contrôles utilisent le cloud d'un projet ;
#   - SSH vers osctl01, oscmp01, oscmp02 (admin + sudo -n) et ceph01 (cephadm shell) ;
#   - API GitLab (jeton des checks) pour lire la branche main des projets ;
#   - SSH vers les instances d'essai (utilisateur debian, clé de adm01), known_hosts temporaire.

_M10O_CLOUD="${WB_OS_CLOUD:-medisphere-admin}"
_M10O_CLOUD_DEV="${WB_OS_CLOUD_DEV:-medisphere-mediagenda-dev}"
_M10O_DOMAINE=medisphere
_M10O_CFG="$HOME/.config/workbook"
_M10O_PROJET_OS="projects/plateforme%2Fopenstack"
_M10O_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M10O_PROJET_INFRA="projects/plateforme%2Finfra"
_M10O_PROJET_DOC="projects/plateforme%2Fmedisphere"
_M10O_CTL=osctl01
_M10O_CALCULS="oscmp01 oscmp02"
_M10O_CEPH="${WB_CEPH_HOST:-ceph01}"
_M10O_DELAI=90

_M10O_TMP="$(mktemp -d)"
trap 'rm -rf "$_M10O_TMP"' EXIT

# _m10o_os ARGS… — client OpenStack avec le cloud des vérifications ; sortie vide si erreur.
_m10o_os() {
  timeout "$_M10O_DELAI" openstack --os-cloud "$_M10O_CLOUD" "$@" 2>/dev/null
}

# _m10o_osc CLOUD ARGS… — client OpenStack avec un autre cloud (droits d'un utilisateur).
_m10o_osc() {
  local cloud="$1"
  shift
  timeout "$_M10O_DELAI" openstack --os-cloud "$cloud" "$@" 2>/dev/null
}

# _m10o_cloud_existe CLOUD — le cloud est déclaré dans clouds.yaml (sans contacter l'API).
_m10o_cloud_existe() {
  grep -Eq "^[[:space:]]+$1:[[:space:]]*$" "$HOME/.config/openstack/clouds.yaml" 2>/dev/null
}

# _m10o_projet_id NOM — identifiant d'un projet du domaine medisphere (vide si absent).
_m10o_projet_id() {
  _m10o_os project show -f value -c id --domain "$_M10O_DOMAINE" "$1" || true
}

# _m10o_serveur NOM — JSON de « server show » de l'instance NOM (tous projets), vide si absente
# ou ambiguë.
_m10o_serveur() {
  local id
  id="$(_m10o_os server list --all-projects --name "^$1\$" -f json \
    | jq -r 'if length == 1 then .[0].ID else empty end' 2>/dev/null || true)"
  [[ -n "$id" ]] || return 0
  _m10o_os server show -f json "$id" || true
}

# _m10o_ip_flottante JSON_SERVEUR — première adresse de 10.10.52.0/24 de l'instance (vide sinon).
_m10o_ip_flottante() {
  jq -r '.addresses | tostring | [match("10\\.10\\.52\\.[0-9]+"; "g").string] | first // empty' <<<"$1" 2>/dev/null || true
}

# _m10o_volume NOM — JSON de « volume show » du volume NOM (tous projets), vide si absent.
_m10o_volume() {
  local id
  id="$(_m10o_os volume list --all-projects --name "$1" -f json \
    | jq -r 'if length == 1 then .[0].ID else empty end' 2>/dev/null || true)"
  [[ -n "$id" ]] || return 0
  _m10o_os volume show -f json "$id" || true
}

# _m10o_ssh_instance IP COMMANDE — commande dans une instance (utilisateur debian, clé de adm01).
_m10o_ssh_instance() {
  local ip="$1"
  shift
  timeout 60 ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$_M10O_TMP/known_hosts" -o LogLevel=ERROR "debian@$ip" -- "$@"
}

# _m10o_ceph COMMANDE… — commande Ceph (lecture) dans « cephadm shell » sur ceph01.
_m10o_ceph() {
  remote "$_M10O_CEPH" "sudo -n cephadm shell -- $*" 2>/dev/null || true
}

# _m10o_fichier_main PROJET CHEMIN — le fichier existe sur la branche main.
_m10o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m10o_contenu_main PROJET CHEMIN — contenu brut d'un fichier de main (vide si absent).
_m10o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m10o_arbre_main PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif, branche main).
_m10o_arbre_main() {
  local chemin page=1 lot
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  while :; do
    lot="$(gitlab_api "$1/repository/tree?path=$chemin&ref=main&recursive=true&per_page=100&page=$page" 2>/dev/null || true)"
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$lot" 2>/dev/null || true
    [[ "$(jq 'length' <<<"$lot" 2>/dev/null || echo 0)" -eq 100 ]] || break
    page=$((page + 1))
  done
}

# _m10o_globals — configuration Kolla de plateforme/openstack (branche main) telle que Kolla la
# lit : etc/kolla/globals.yml, puis etc/kolla/globals.d/*.yml par ordre alphabétique.
_m10o_globals() {
  local f
  _m10o_contenu_main "$_M10O_PROJET_OS" etc/kolla/globals.yml
  while IFS= read -r f; do
    [[ "$f" == *.yml ]] && { echo; _m10o_contenu_main "$_M10O_PROJET_OS" "$f"; }
  done < <(_m10o_arbre_main "$_M10O_PROJET_OS" etc/kolla/globals.d | sort)
  return 0
}

# _m10o_globals_vaut TEXTE VARIABLE REGEX — dans TEXTE (sortie de _m10o_globals), la DERNIÈRE ligne
# non commentée « VARIABLE: valeur » (celle qui l'emporte) a une valeur, sans guillemets, qui
# correspond à la regex étendue.
_m10o_globals_vaut() {
  sed -nE "s/^$2:[[:space:]]*[\"']?([^\"'#]*)[\"']?[[:space:]]*(#.*)?\$/\\1/p" <<<"$1" \
    | sed -E 's/[[:space:]]+$//' | tail -n 1 | grep -Eqx -- "$3"
}

# _m10o_matrice — matrice des flux de la bordure (plateforme/ansible, main) : premier
# emplacement trouvé (host_vars de gw01, ou fichier commun aux passerelles depuis M07).
_m10o_matrice() {
  local c contenu
  for c in inventories/lab/host_vars/gw01/pare_feu.yml \
           inventories/lab/group_vars/passerelles/pare_feu.yml \
           inventories/lab/group_vars/role_routeur/pare_feu.yml; do
    contenu="$(_m10o_contenu_main "$_M10O_PROJET_ANSIBLE" "$c")"
    if [[ -n "$contenu" ]]; then
      printf '%s\n' "$contenu"
      return 0
    fi
  done
  return 0
}

# _m10o_mode600 FICHIER — le fichier existe, n'est pas vide, et est en mode 600.
_m10o_mode600() {
  [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]
}

# _m10o_conf_noeud HÔTE FICHIER — contenu d'un fichier de configuration généré par Kolla.
_m10o_conf_noeud() {
  remote "$1" "sudo -n cat $2" 2>/dev/null || true
}

# _m10o_ini_vaut TEXTE CLÉ REGEX — dans un INI, une ligne « clé = valeur » dont la valeur
# correspond à la regex étendue (sections ignorées : les clés de ce palier sont uniques).
_m10o_ini_vaut() {
  sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*)\$/\\1/p" <<<"$1" \
    | sed -E 's/[[:space:]]+$//' | grep -Eqx -- "$3"
}

# _m10o_rp_uuid NOM — identifiant du fournisseur de ressources Placement d'un calcul.
_m10o_rp_uuid() {
  _m10o_os resource provider list -f json \
    | jq -r --arg n "$1" '.[] | select(.name == $n or (.name | startswith($n + "."))) | .uuid' 2>/dev/null \
    | head -n 1 || true
}
