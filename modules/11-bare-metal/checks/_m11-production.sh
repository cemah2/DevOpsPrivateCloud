# shellcheck shell=bash
# _m11-production.sh — fonctions partagées par les vérifications du palier 3 du module 11
# (check-E13 à check-E18) et reprises par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Lecture seule : curl (GET, et POST sans jeton vers le service de réponse PVE, qui ne modifie
# rien), openssl, ssh (commandes de lecture), API NetBox et GitLab en GET, Redfish en GET.
# Préfixe _m11p_ : évite les collisions quand le mini-projet charge plusieurs fichiers d'aide.

_m11p_zone="par1.medisphere.internal"
_m11p_pxe_fqdn="pxe01.$_m11p_zone"
_m11p_pxe_ip=10.10.60.10
_m11p_src="${WB_SRC:-$HOME/src}"
_m11p_cfg="$HOME/.config/workbook"
_m11p_ilo_env="${WB_ILO_ENV_FILE:-$_m11p_cfg/ilo-hp01.env}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m11p_vmid=([pxe01]=2111 [bm01]=2112 [bm02]=2113 [bm03]=2114 [bm04]=2115 [maas01]=2116)

# _m11p_https CHEMIN [options curl…] — code de sortie de curl en HTTPS vérifié vers pxe01 depuis
# adm01, sans dépendre du DNS (0 = 2xx, 22 = 4xx/5xx, 60 = certificat refusé, 7 = refus).
_m11p_https() {
  local chemin="$1" rc=0
  shift
  curl -sS --fail -o /dev/null --max-time 15 --resolve "$_m11p_pxe_fqdn:443:$_m11p_pxe_ip" "$@" \
    "https://$_m11p_pxe_fqdn$chemin" 2>/dev/null || rc=$?
  printf '%s\n' "$rc"
}

# _m11p_https_contenu CHEMIN — contenu servi par pxe01 (HTTPS vérifié).
_m11p_https_contenu() {
  curl -sS --fail --max-time 15 --resolve "$_m11p_pxe_fqdn:443:$_m11p_pxe_ip" \
    "https://$_m11p_pxe_fqdn$1" 2>/dev/null
}

# _m11p_https_code CHEMIN [options curl…] — code HTTP (000 si pas de réponse).
_m11p_https_code() {
  local chemin="$1"
  shift
  curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$_m11p_pxe_fqdn:443:$_m11p_pxe_ip" "$@" \
    "https://$_m11p_pxe_fqdn$chemin" 2>/dev/null || true
}

# _m11p_pki_ok — pxe01 présente une chaîne complète dont la feuille vient de l'intermédiaire MédiSphère.
_m11p_pki_ok() {
  local c
  c="$(openssl s_client -connect "$_m11p_pxe_ip:443" -servername "$_m11p_pxe_fqdn" -showcerts </dev/null 2>/dev/null)"
  [[ "$(grep -c 'BEGIN CERTIFICATE' <<<"$c")" -ge 2 ]] || return 1
  sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' <<<"$c" | awk '{ print } /END CERTIFICATE/ { exit }' \
    | openssl x509 -noout -issuer -nameopt utf8,sep_comma_plus 2>/dev/null | grep -q 'Intermediate CA'
}

# _m11p_racine_nginx — racine servie par nginx sur pxe01 (configuration chargée).
_m11p_racine_nginx() {
  remote pxe01 "sudo -n nginx -T 2>/dev/null | sed -nE 's/^[[:space:]]*root[[:space:]]+([^;]+);.*/\1/p' | head -n 1" 2>/dev/null
}

# _m11p_tftp_ok FICHIER… — 0 si chaque fichier se lit en TFTP sur 10.10.60.10, sonde lancée SUR
# pxe01 (premier bloc de données reçu ; programme Python envoyé par l'entrée standard de ssh).
_m11p_tftp_ok() {
  remote pxe01 "python3 - $*" >/dev/null 2>&1 <<PY
import socket, sys
for f in sys.argv[1:]:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(4)
    s.sendto(b"\\x00\\x01" + f.encode() + b"\\x00octet\\x00", ("$_m11p_pxe_ip", 69))
    try:
        d, _ = s.recvfrom(1024)
    except OSError:
        sys.exit(1)
    if d[:2] != b"\\x00\\x03":
        sys.exit(1)
PY
}

# _m11p_gitlab_fichier PROJET CHEMIN — le fichier existe sur la branche par défaut du projet.
_m11p_gitlab_fichier() {
  local p c
  p="$(jq -rn --arg s "$1" '$s|@uri')"
  c="$(jq -rn --arg s "$2" '$s|@uri')"
  gitlab_api "projects/$p/repository/files/$c?ref=main" >/dev/null 2>&1
}

# _m11p_gitlab_brut PROJET CHEMIN — contenu du fichier sur main.
_m11p_gitlab_brut() {
  local p c
  p="$(jq -rn --arg s "$1" '$s|@uri')"
  c="$(jq -rn --arg s "$2" '$s|@uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null
}

# _m11p_gitlab_ls PROJET DOSSIER — noms des fichiers d'un dossier sur main.
_m11p_gitlab_ls() {
  local p d
  p="$(jq -rn --arg s "$1" '$s|@uri')"
  d="$(jq -rn --arg s "$2" '$s|@uri')"
  gitlab_api "projects/$p/repository/tree?path=$d&ref=main&per_page=100" 2>/dev/null | jq -r '.[].name' 2>/dev/null
}

# _m11p_equipement NOM — objet NetBox (JSON) de l'équipement NOM.
_m11p_equipement() {
  netbox_api "dcim/devices/?name=$1" 2>/dev/null | jq -c '.results[0] // empty' 2>/dev/null
}

# _m11p_bm_actifs — lignes « nom ip » des équipements serveur-bm à l'état active.
_m11p_bm_actifs() {
  netbox_api "dcim/devices/?role=serveur-bm&status=active&limit=50" 2>/dev/null \
    | jq -r '.results[] | "\(.name) \((.primary_ip4.address // "") | split("/")[0])"' 2>/dev/null
}

# _m11p_ilo CHEMIN — GET Redfish sur l'iLO de hp01 (identifiants lus dans ilo-hp01.env et passés
# à curl par son entrée standard, jamais en argument ; certificat épinglé si ILO_CACERT est défini).
_m11p_ilo() {
  [[ -r "$_m11p_ilo_env" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    source "$_m11p_ilo_env"
    set +a
    local -a ca=()
    if [[ -n "${ILO_CACERT:-}" ]]; then ca=(--cacert "$ILO_CACERT"); fi
    printf 'user = "%s:%s"\n' "$ILO_USER" "$ILO_PASSWORD" \
      | curl -sS --fail --max-time 20 -K- "${ca[@]}" "https://$ILO_HOST$1"
  ) 2>/dev/null
}

# _m11p_ansible COMMANDE [args…] — comme l'apprenant : racine du projet ansible, environnement du
# projet, jeton NetBox (NETBOX_TOKEN, sinon netbox-ansible.env, à défaut le jeton des checks).
_m11p_ansible() {
  local cmd="$1"
  shift
  (
    cd "$_m11p_src/ansible" || exit 1
    set -a
    if [[ -r "$_m11p_cfg/pve-ansible.env" ]]; then
      # shellcheck source=/dev/null
      source "$_m11p_cfg/pve-ansible.env"
    fi
    if [[ -z "${NETBOX_TOKEN:-}" && -r "$_m11p_cfg/netbox-ansible.env" ]]; then
      # shellcheck source=/dev/null
      source "$_m11p_cfg/netbox-ansible.env"
    fi
    set +a
    if [[ -z "${NETBOX_TOKEN:-}" && -r "${WB_NETBOX_TOKEN_FILE:-$_m11p_cfg/netbox-checks.token}" ]]; then
      NETBOX_TOKEN="$(<"${WB_NETBOX_TOKEN_FILE:-$_m11p_cfg/netbox-checks.token}")"
      export NETBOX_TOKEN
    fi
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    if [[ -x ".venv/bin/$cmd" ]]; then
      exec ".venv/bin/$cmd" "$@" </dev/null
    fi
    exec uv run --frozen --quiet "$cmd" "$@" </dev/null
  )
}

# _m11p_aucune_panne_active [EXX…] — aucune des pannes listées (ou M11-* si aucune) n'est marquée.
_m11p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M11-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M11-$e" ]] || return 1
  done
}
