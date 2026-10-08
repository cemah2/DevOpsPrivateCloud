# shellcheck shell=bash
# _m10-decouverte.sh — fonctions partagées par les checks M10-E02 à M10-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m10d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
# OpenStack est interrogé par la CLI de adm01 avec des commandes de LECTURE (list, show, token
# issue) ; le cloud vient de WB_OS_CLOUD (lab/lab.env), medisphere-admin par défaut.

_M10D_CLOUD="${WB_OS_CLOUD:-medisphere-admin}"
_M10D_SRC="${WB_SRC:-$HOME/src}"
_M10D_OS="$_M10D_SRC/openstack"
_M10D_INFRA="$_M10D_SRC/infra"
_M10D_ANSIBLE="$_M10D_SRC/ansible"
_M10D_DNS="10.10.20.10"
_M10D_RACINE_SYS="/usr/local/share/ca-certificates/medisphere-root-ca.crt"
_M10D_NOM_EXT="openstack.par1.medisphere.internal"

# _m10d_racine — certificat PUBLIC de la racine MédiSphère (magasin de adm01, sinon dépôt Ansible).
_m10d_racine() {
  local f
  for f in "$_M10D_RACINE_SYS" "$_M10D_ANSIBLE/pki/medisphere-root-ca.crt"; do
    [[ -s "$f" ]] && { echo "$f"; return 0; }
  done
  echo "/nonexistent/medisphere-root-ca.crt"
}

# _m10d_os [--os-cloud X] ARGS… — sortie JSON d'une commande de lecture de la CLI openstack
# (vide en cas d'échec). Cloud par défaut : WB_OS_CLOUD.
_m10d_os() {
  local cloud="$_M10D_CLOUD"
  if [[ "${1:-}" == "--os-cloud" ]]; then cloud="$2"; shift 2; fi
  timeout 60 openstack --os-cloud "$cloud" "$@" -f json 2>/dev/null || true
}

# _m10d_os_ok [--os-cloud X] ARGS… — la commande (de lecture) réussit.
_m10d_os_ok() {
  local cloud="$_M10D_CLOUD"
  if [[ "${1:-}" == "--os-cloud" ]]; then cloud="$2"; shift 2; fi
  timeout 60 openstack --os-cloud "$cloud" "$@" >/dev/null 2>&1
}

# _m10d_jq JSON FILTRE — vrai si le filtre jq (-e) est vrai sur le JSON donné.
_m10d_jq() {
  [[ -n "$1" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"
}

# _m10d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m10d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m10d_carte CONFIG NETN BRIDGE MAC [MTU] — la carte netN est virtio, sur ce VNet, avec cette
# MAC (casse ignorée), cette MTU si donnée, et sans pare-feu Proxmox.
_m10d_carte() {
  local ligne
  ligne="$(grep -E "^$2: " <<<"$1" | head -n 1)"
  [[ -n "$ligne" ]] || return 1
  grep -qiE "(^|[ ,])virtio=$4(,|$)" <<<"${ligne#*: }" || return 1
  grep -qE "(^|,)bridge=$3(,|$)" <<<"${ligne#*: }" || return 1
  if [[ -n "${5:-}" ]]; then grep -qE "(^|,)mtu=$5(,|$)" <<<"${ligne#*: }" || return 1; fi
  ! grep -qE "(^|,)firewall=1(,|$)" <<<"${ligne#*: }"
}

# _m10d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m10d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m10d_dans_pool VMID — la VM est membre du pool lab.
_m10d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m10d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab
# (PROJET au format groupe/projet).
_m10d_fichier_main() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c?ref=main" >/dev/null 2>&1
}

# _m10d_vault_critique FICHIER — fichier chiffré par Ansible Vault sous l'identité « critique ».
_m10d_vault_critique() {
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête
  head -n 1 "$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique'
}

# _m10d_mode FICHIER MODE — le fichier existe, n'est pas vide, et a exactement ce mode.
_m10d_mode() {
  [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == "$2" ]]
}

# _m10d_chaine_ok HÔTE PORT [NOM] — la chaîne présentée se vérifie avec la SEULE racine
# MédiSphère et le certificat est valable pour NOM (défaut : HÔTE).
_m10d_chaine_ok() {
  local hote="$1" port="$2" nom="${3:-$1}" d rc=1
  d="$(mktemp -d)"
  timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:$port" -servername "$nom" -showcerts </dev/null 2>/dev/null \
    | awk -v d="$d" '/BEGIN CERTIFICATE/ {n++; dedans=1} dedans {print > (d "/c" n ".pem")} /END CERTIFICATE/ {dedans=0}'
  if [[ -s "$d/c1.pem" ]]; then
    cat "$d"/c[2-9].pem >"$d/inter.pem" 2>/dev/null || true
    openssl verify -no-CApath -no-CAstore -CAfile "$(_m10d_racine)" -untrusted "$d/inter.pem" \
      -verify_hostname "$nom" "$d/c1.pem" >/dev/null 2>&1 && rc=0
  fi
  rm -rf "$d"
  return "$rc"
}

# _m10d_id_projet NOM — identifiant d'un projet du domaine medisphere (vide si absent).
_m10d_id_projet() {
  _m10d_os project show "$1" --domain medisphere | jq -r '.id // empty' 2>/dev/null || true
}
