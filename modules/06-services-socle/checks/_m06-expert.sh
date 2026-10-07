# shellcheck shell=bash
# _m06-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du
# module 06 (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule :
# dig, curl, openssl, ssh (commandes de lecture), API NetBox et GitLab en GET, ansible-inventory.
# Préfixe _m06x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m06x_zone="par1.medisphere.internal"
_m06x_ansible_dir="${WB_SRC:-$HOME/src}/ansible"
_m06x_cfg="$HOME/.config/workbook"
_m06x_netbox_url="${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m06x_ip=([gw01]=10.10.10.1 [adm01]=10.10.10.10 [dns01]=10.10.20.10 [ca01]=10.10.20.11
  [git01]=10.10.20.12 [nbx01]=10.10.20.13 [s3-01]=10.10.20.14 [runner01]=10.10.20.15 [dns02]=10.10.20.16)
# shellcheck disable=SC2034
declare -A _m06x_vmid=([gw01]=1000 [adm01]=1001 [dns01]=1002 [ca01]=1003 [git01]=1004 [nbx01]=1005
  [s3-01]=1006 [runner01]=1007 [dns02]=1008)
# Hôtes Debian du socle joints en admin + sudo -n (gw01 compris) ; adm01 est le poste local.
# shellcheck disable=SC2034
_m06x_hotes=(gw01 dns01 ca01 git01 nbx01 s3-01 runner01 dns02)

# _m06x_resout NOM IP [SERVEUR] — le serveur (dns01 par défaut) répond exactement IP pour NOM.
_m06x_resout() {
  dig +short +time=3 +tries=1 "@${3:-10.10.20.10}" "$1" A 2>/dev/null | grep -qx "$2"
}

# _m06x_statut SERVEUR NOM TYPE [options dig…] — statut DNS (NOERROR, SERVFAIL…) ou TIMEOUT.
_m06x_statut() {
  local srv="$1" nom="$2" type="$3" o s
  shift 3
  o="$(dig +time=3 +tries=1 "@$srv" "$nom" "$type" "$@" 2>&1)" || true
  s="$(sed -nE 's/.*status: ([A-Z]+).*/\1/p' <<<"$o" | head -n 1)"
  printf '%s\n' "${s:-TIMEOUT}"
}

# _m06x_valide SERVEUR NOM TYPE — réponse validée DNSSEC (drapeau ad) par le récurseur.
_m06x_valide() {
  dig +dnssec +time=3 +tries=1 "@$1" "$2" "$3" 2>/dev/null | grep -Eq '^;; flags:[a-z ]* ad[ ;]'
}

# _m06x_https_ok FQDN IP [PORT] [CHEMIN] — HTTPS avec vérification du certificat par le magasin
# système de adm01, sans dépendre du DNS (curl --resolve).
_m06x_https_ok() {
  local p="${3:-443}"
  curl -sS -o /dev/null --max-time 10 --resolve "$1:$p:$2" "https://$1:$p${4:-/}" 2>/dev/null
}

# _m06x_chaine FQDN IP [PORT] — certificats présentés par le serveur (sortie de openssl s_client).
_m06x_chaine() {
  openssl s_client -connect "$2:${3:-443}" -servername "$1" -showcerts </dev/null 2>/dev/null
}

# _m06x_feuille FQDN IP [PORT] — certificat feuille présenté, au format PEM.
_m06x_feuille() {
  _m06x_chaine "$@" | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' | awk '{ print } /END CERTIFICATE/ { exit }'
}

# _m06x_emis_par_pki FQDN IP [PORT] — feuille émise par l'intermédiaire MédiSphère (step-ca), chaîne
# complète (au moins deux certificats présentés).
_m06x_emis_par_pki() {
  local c
  c="$(_m06x_chaine "$@")"
  [[ "$(grep -c 'BEGIN CERTIFICATE' <<<"$c")" -ge 2 ]] || return 1
  _m06x_feuille "$@" | openssl x509 -noout -issuer -nameopt utf8,sep_comma_plus 2>/dev/null | grep -q 'Intermediate CA'
}

# _m06x_duree_ok FQDN IP [PORT] — durée de validité ≤ 31 jours et plus de 10 jours restants.
_m06x_duree_ok() {
  local pem debut fin
  pem="$(_m06x_feuille "$@")"
  [[ -n "$pem" ]] || return 1
  debut="$(date -d "$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  (((fin - debut) <= 31 * 86400 && (fin - $(date +%s)) > 10 * 86400))
}

# _m06x_ssh_neuf HÔTE — nouvelle connexion SSH (sans multiplexage) : clé d'hôte et identité vérifiées.
_m06x_ssh_neuf() {
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1
}

# _m06x_existe HÔTE — l'hôte répond en SSH (hôtes facultatifs selon l'avancement).
_m06x_existe() { remote "$1" true >/dev/null 2>&1; }

# _m06x_ansible COMMANDE [args…] — comme l'apprenant : racine du projet, environnement du projet ;
# jeton NetBox : NETBOX_TOKEN de l'environnement, à défaut le jeton en lecture des checks.
_m06x_ansible() {
  local cmd="$1"
  shift
  (
    cd "$_m06x_ansible_dir" || exit 1
    if [[ -r "$_m06x_cfg/pve-ansible.env" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$_m06x_cfg/pve-ansible.env"
      set +a
    fi
    if [[ -z "${NETBOX_TOKEN:-}" && -r "${WB_NETBOX_TOKEN_FILE:-$_m06x_cfg/netbox-checks.token}" ]]; then
      NETBOX_TOKEN="$(<"${WB_NETBOX_TOKEN_FILE:-$_m06x_cfg/netbox-checks.token}")"
      export NETBOX_TOKEN
    fi
    export NETBOX_API="${NETBOX_API:-$_m06x_netbox_url}"
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    if [[ -x ".venv/bin/$cmd" ]]; then
      exec ".venv/bin/$cmd" "$@" </dev/null
    fi
    exec uv run --frozen --quiet "$cmd" "$@" </dev/null
  )
}

# _m06x_inv_netbox — fichier (relatif au projet) de l'inventaire NetBox (M06-E12).
_m06x_inv_netbox() {
  local f
  f="$(grep -rlE '^[[:space:]]*plugin:[[:space:]]*["'\'']?netbox\.netbox\.nb_inventory' \
    "$_m06x_ansible_dir/inventories" 2>/dev/null | sort | head -n 1)"
  [[ -n "$f" ]] || return 1
  printf '%s\n' "${f#"$_m06x_ansible_dir"/}"
}

# _m06x_hotes_groupe JSON GROUPE — hôtes d'un groupe (récursivement) d'une sortie --list.
_m06x_hotes_groupe() {
  jq -r --arg g "$2" '. as $inv
    | def h($g): ($inv[$g].hosts // []) + (($inv[$g].children // []) | map(h(.)) | add // []);
    h($g) | unique | .[]' <<<"$1" 2>/dev/null
}

# _m06x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M06-* si aucune) n'est marquée.
_m06x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    # Pas de glob ici : lab/bin/check active nullglob (un motif sans correspondance disparaîtrait).
    [[ -z "$(find "$d" -maxdepth 1 -name 'M06-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M06-$e" ]] || return 1
  done
}

# _m06x_service_kea4 — commande distante qui affiche le nom réel de l'unité kea-dhcp4.
# shellcheck disable=SC2016
_m06x_kea4='k=""; for s in isc-kea-dhcp4-server kea-dhcp4-server kea-dhcp4; do if systemctl cat "$s" >/dev/null 2>&1; then k="$s"; break; fi; done'
# shellcheck disable=SC2016,SC2034
_m06x_d2='d=""; for s in isc-kea-dhcp-ddns-server kea-dhcp-ddns-server kea-dhcp-ddns; do if systemctl cat "$s" >/dev/null 2>&1; then d="$s"; break; fi; done'
