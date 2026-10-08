# shellcheck shell=bash
# _m07-operationnel.sh — fonctions partagées par les checks M07-E10 à M07-E20 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m07o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
# Hôtes de la maquette (hap01, srv01, leaf01, lyo-gw01…) : joints en SSH par leur nom court depuis
# adm01, comme les hôtes du socle (mise en place en M07-E03).

_M07O_ZONE="par1.medisphere.internal"
_M07O_RACINE="/usr/local/share/ca-certificates/medisphere-root-ca.crt"
_M07O_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M07O_PROJET_DOC="projects/plateforme%2Fmedisphere"
_M07O_PROJET_OUTILS="projects/plateforme%2Foutils"
_M07O_PROJET_INFRA="projects/plateforme%2Finfra"
_M07O_PVE="${WB_PVE_HOST:-pve01}"

# _m07o_fichier_main PROJET CHEMIN [REF] — le fichier existe sur la référence (main par défaut).
_m07o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}

# _m07o_contenu_main PROJET CHEMIN [REF] — contenu brut d'un fichier du dépôt (vide si absent).
_m07o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m07o_cherche_main PROJET REGEX_CHEMIN — premier chemin de l'arbre de main qui correspond.
_m07o_cherche_main() {
  gitlab_api "$1/repository/tree?ref=main&recursive=true&per_page=100&pagination=keyset" 2>/dev/null \
    | jq -r --arg r "$2" '.[] | select(.type == "blob") | .path | select(test($r))' 2>/dev/null | head -n 1 || true
}

# _m07o_vm_config VMID — configuration Proxmox de la VM (qm config, lue en root sur pve01).
_m07o_vm_config() {
  remote "$_M07O_PVE" "qm config $1" 2>/dev/null || true
}

# _m07o_vm_existe VMID — la VM existe sur pve01.
_m07o_vm_existe() {
  remote "$_M07O_PVE" "qm status $1" >/dev/null 2>&1
}

# _m07o_haproxy_stat HÔTE — sortie CSV de « show stat » (socket d'administration d'HAProxy).
_m07o_haproxy_stat() {
  remote "$1" 'echo "show stat" | sudo -n socat stdio unix-connect:/run/haproxy/admin.sock' 2>/dev/null || true
}

# _m07o_etat_serveur CSV PROXY SERVEUR — état (champ 18) d'un serveur dans la sortie de show stat.
_m07o_etat_serveur() {
  awk -F, -v p="$2" -v s="$3" '$1 == p && $2 == s {print $18}' <<<"$1" | head -n 1
}

# _m07o_vtysh HÔTE COMMANDE — sortie d'une commande vtysh (en root sur l'hôte).
_m07o_vtysh() {
  remote "$1" "sudo -n vtysh -c '$2'" 2>/dev/null || true
}

# _m07o_cert_tls HÔTE PORT [SNI] — certificat présenté (texte d'openssl x509), vide si échec.
_m07o_cert_tls() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" -servername "${3:-$1}" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || true
}

# _m07o_mtu HÔTE INTERFACE — MTU d'une interface d'un hôte (vide si absente).
_m07o_mtu() {
  remote "$1" "cat /sys/class/net/$2/mtu" 2>/dev/null || true
}

# _m07o_curl URL [OPTIONS…] — code HTTP d'un GET vérifié par la racine MédiSphère.
_m07o_curl() {
  local url="$1"
  shift
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_M07O_RACINE" "$@" "$url" 2>/dev/null || true
}

# _m07o_nft_gw01 CHAÎNE — règles d'une chaîne de gw01 (table inet filter, ou « nat CHAÎNE »).
_m07o_nft_gw01() {
  if [[ "$1" == nat\ * ]]; then
    remote gw01 "sudo -n nft list chain ip nat ${1#nat }" 2>/dev/null || true
  else
    remote gw01 "sudo -n nft list chain inet filter $1" 2>/dev/null || true
  fi
}

# _m07o_contenu_dossier PROJET DOSSIER [REGEX_NOM] — contenu concaténé des fichiers d'un dossier
# du dépôt (main, non récursif), filtrés par nom ; vide si absent.
_m07o_contenu_dossier() {
  local projet="$1" dossier="$2" motif="${3:-.}" f
  gitlab_api "$projet/repository/tree?ref=main&path=$(jq -rn --arg v "$dossier" '$v | @uri')&per_page=100" 2>/dev/null \
    | jq -r --arg r "$motif" '.[] | select(.type == "blob") | .path | select(test($r))' 2>/dev/null \
    | while read -r f; do _m07o_contenu_main "$projet" "$f"; done || true
}
