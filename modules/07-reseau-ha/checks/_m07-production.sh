# shellcheck shell=bash
# _m07-production.sh — fonctions partagées par les checks M07-E24 à M07-E34 et M07-E46 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Accès : pve01 en root (WB_PVE_HOST), pbs01 en root (WB_PBS_HOST), gw01/gw02/lb01/lb02 en admin +
# sudo -n (noms de ~/.ssh/config : gw01 = 10.10.10.2, gw02 = 10.10.10.3 à partir de M07-E25),
# API GitLab et NetBox en lecture (jetons des checks), copies de travail sous WB_SRC et WB_DEPOT.
# Variables de lab/lab.env propres au module 07 (introduction du module) :
#   WB_GW01_WAN, WB_GW02_WAN  adresses WAN propres des passerelles (<IP-GW01-WAN>, <IP-GW02-WAN>)
#   WB_GW_WAN_VIP             VIP WAN de la bordure (<IP-GW-WAN-VIP>)
# Préfixe _m07p_ : évite les collisions quand check-E46 charge ce fichier avec d'autres.

_M07P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M07P_ZONE=par1.medisphere.internal
_M07P_ANSIBLE="${WB_SRC:-$HOME/src}/ansible"
_M07P_INFRA="${WB_SRC:-$HOME/src}/infra"
_M07P_DEPOT="${WB_DEPOT:-$HOME/medisphere}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
_M07P_VLANS=(10 20 30 40 50 52 60 70 99)
# shellcheck disable=SC2034
_M07P_PASSERELLES=(gw01 gw02)
# shellcheck disable=SC2034
_M07P_REPARTITEURS=(lb01 lb02)

# --- Proxmox (root sur pve01) --------------------------------------------------------------------

_M07P_VMS_CACHE=""
# _m07p_vms — JSON de /cluster/resources (VMs), en cache. Échoue si pve01 ne répond pas.
_m07p_vms() {
  if [[ -z "$_M07P_VMS_CACHE" ]]; then
    _M07P_VMS_CACHE="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" \
      || _M07P_VMS_CACHE="indisponible"
    jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$_M07P_VMS_CACHE" || _M07P_VMS_CACHE="indisponible"
  fi
  [[ "$_M07P_VMS_CACHE" != "indisponible" ]] || return 1
  printf '%s\n' "$_M07P_VMS_CACHE"
}
# _m07p_charger — remplit le cache dans le shell courant (à appeler en tête de chaque check).
_m07p_charger() { _m07p_vms >/dev/null || true; }

# _m07p_vm_jq VMID FILTRE_JQ — applique un filtre booléen à la VM (échoue si absente).
_m07p_vm_jq() {
  local v
  v="$(_m07p_vms)" || return 1
  jq -e --argjson id "$1" "[.[] | select(.vmid == \$id)] | length == 1 and (.[0] | $2)" >/dev/null <<<"$v"
}

# _m07p_vm_etiquettes VMID ETIQUETTE... — la VM porte toutes ces étiquettes Proxmox.
_m07p_vm_etiquettes() {
  local id="$1" e
  shift
  for e in "$@"; do
    _m07p_vm_jq "$id" "((.tags // \"\") | split(\";\") | index(\"$e\")) != null" || return 1
  done
}

# _m07p_vm_tourne VMID — la VM existe et tourne (contrôles facultatifs : maquette).
_m07p_vm_tourne() { _m07p_vm_jq "$1" '.status == "running"'; }

# _m07p_aucune_vm_entre MIN MAX — aucune VM dans cette plage de VMID (échoue si pve01 muet).
_m07p_aucune_vm_entre() {
  local v
  v="$(_m07p_vms)" || return 1
  ! jq -e --argjson a "$1" --argjson b "$2" 'any(.[]; .vmid >= $a and .vmid <= $b)' >/dev/null <<<"$v"
}

# _m07p_clone_complet VMID — aucun disque de la VM ne dépend d'un template.
_m07p_clone_complet() {
  remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null \
    | awk '/^(scsi|virtio|sata|ide)[0-9]+:/ && !/media=cdrom/ && !/cloudinit/' \
    | { ! grep -q 'base-[0-9]*-disk'; }
}

# _m07p_qm_config VMID — configuration Proxmox de la VM (texte).
_m07p_qm_config() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null; }

# --- Adresses et VRRP ------------------------------------------------------------------------------

declare -A _M07P_ADR=()
# _m07p_adresses HÔTE — adresses IPv4 portées (une par ligne), en cache. Échoue si l'hôte est muet.
_m07p_adresses() {
  local h="$1" a
  if [[ -z "${_M07P_ADR[$h]+x}" ]]; then
    a="$(remote "$h" "ip -j -4 address show" 2>/dev/null | jq -r '.[].addr_info[].local' 2>/dev/null)" || a=""
    _M07P_ADR[$h]="$a"
  fi
  [[ -n "${_M07P_ADR[$h]}" ]] || return 1
  printf '%s\n' "${_M07P_ADR[$h]}"
}
# _m07p_charger_adresses HÔTE... — remplit le cache dans le shell courant.
_m07p_charger_adresses() {
  local h
  for h in "$@"; do _m07p_adresses "$h" >/dev/null || true; done
}

# _m07p_porte HÔTE IP — l'hôte porte cette adresse.
_m07p_porte() { _m07p_adresses "$1" 2>/dev/null | grep -qx "$2"; }

# _m07p_porteurs IP HÔTE... — noms des hôtes qui portent l'adresse (une ligne par hôte).
_m07p_porteurs() {
  local ip="$1" h
  shift
  for h in "$@"; do
    _m07p_porte "$h" "$ip" && printf '%s\n' "$h"
  done
  return 0
}

# _m07p_vip_unique IP HÔTE... — exactement un des hôtes porte l'adresse (tous doivent répondre).
_m07p_vip_unique() {
  local ip="$1" h n=0
  shift
  for h in "$@"; do
    _m07p_adresses "$h" >/dev/null || return 1
    _m07p_porte "$h" "$ip" && n=$((n + 1))
  done
  ((n == 1))
}

# _m07p_maitre — passerelle qui porte 10.10.10.1 (vide si aucune ou deux).
_m07p_maitre() {
  local p
  p="$(_m07p_porteurs 10.10.10.1 gw01 gw02)"
  [[ "$(wc -l <<<"$p")" == 1 && -n "$p" ]] && printf '%s\n' "$p"
  return 0
}
# _m07p_secours — l'autre passerelle (vide si pas de maître unique).
_m07p_secours() {
  case "$(_m07p_maitre)" in
    gw01) echo gw02 ;;
    gw02) echo gw01 ;;
    *) return 0 ;;
  esac
}

# _m07p_vips_bordure_ensemble — toutes les VIP des VLAN (et la VIP WAN si connue) sont portées par
# une seule et même passerelle.
_m07p_vips_bordure_ensemble() {
  local m v
  m="$(_m07p_maitre)"
  [[ -n "$m" ]] || return 1
  for v in "${_M07P_VLANS[@]}"; do
    [[ "$(_m07p_porteurs "10.10.$v.1" gw01 gw02)" == "$m" ]] || return 1
  done
  if [[ -n "${WB_GW_WAN_VIP:-}" ]]; then
    [[ "$(_m07p_porteurs "$WB_GW_WAN_VIP" gw01 gw02)" == "$m" ]] || return 1
  fi
}

# _m07p_ruleset HÔTE — jeu de règles nftables chargé, sans compteurs ni numéros (comparable).
_m07p_ruleset() { remote "$1" "sudo -n nft -s list ruleset" 2>/dev/null; }

# _m07p_rulesets_identiques — gw01 et gw02 chargent le même jeu de règles (non vide).
_m07p_rulesets_identiques() {
  local a b
  a="$(_m07p_ruleset gw01)" || return 1
  b="$(_m07p_ruleset gw02)" || return 1
  [[ -n "$a" && "$a" == "$b" ]]
}

# _m07p_bgp_etabli HÔTE VOISIN — la session BGP vers VOISIN est établie sur l'hôte.
_m07p_bgp_etabli() {
  remote "$1" "sudo -n vtysh -c 'show bgp summary json'" 2>/dev/null \
    | jq -e --arg v "$2" '[.. | objects | select(has("peers")) | .peers[$v].state // empty] | any(. == "Established")' >/dev/null 2>&1
}

# --- Dépôts : GitLab (main) et copies de travail -------------------------------------------------

# _m07p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m07p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m07p_doc_main DOSSIER PRÉFIXE — un fichier « PRÉFIXE* » existe dans DOSSIER de plateforme/medisphere (main).
_m07p_doc_main() {
  local d="${1//\//%2F}"
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&per_page=100" 2>/dev/null \
    | jq -e --arg p "$2" 'any(.[]?; .name | startswith($p))' >/dev/null
}

# _m07p_job_reussi PROJET MOTIF — un job de main dont le nom contient MOTIF a réussi (100 derniers).
_m07p_job_reussi() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; .ref == "main" and (.name | contains($m)))' >/dev/null
}

# --- Réseau depuis un hôte ---------------------------------------------------------------------------

# _m07p_port_ferme HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP impossible. Échoue si
# l'hôte source lui-même ne répond pas (sinon : faux positif).
_m07p_port_ferme() {
  remote "$1" true >/dev/null 2>&1 || return 1
  remote "$1" "! timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3' 2>/dev/null"
}

# _m07p_port_ouvert HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP possible.
_m07p_port_ouvert() {
  remote "$1" "timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3'" >/dev/null 2>&1
}

# --- Certificats et HTTPS --------------------------------------------------------------------------

# _m07p_feuille FQDN IP [PORT] — certificat feuille présenté par IP avec le SNI FQDN (PEM).
_m07p_feuille() {
  openssl s_client -connect "$2:${3:-443}" -servername "$1" </dev/null 2>/dev/null | openssl x509 2>/dev/null
}

# _m07p_cert_ok FQDN IP [PORT] — chaîne vérifiée par la racine MédiSphère pour le nom, émis par
# l'intermédiaire, durée ≤ 31 jours, plus de 10 jours restants.
_m07p_cert_ok() {
  local pem debut fin
  openssl s_client -connect "$2:${3:-443}" -servername "$1" -CAfile "$_M07P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null >/dev/null 2>&1 || return 1
  pem="$(_m07p_feuille "$@")"
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -issuer <<<"$pem" 2>/dev/null | grep -q 'Intermediate CA' || return 1
  debut="$(date -d "$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  (((fin - debut) <= 31 * 86400 && (fin - $(date +%s)) > 10 * 86400))
}

# _m07p_code URL — code HTTP (vérification TLS par la racine MédiSphère, sans suivre les redirections).
_m07p_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 --cacert "$_M07P_RACINE" "$1" 2>/dev/null || true
}

# _m07p_entete URL NOM — valeur d'un en-tête de réponse (insensible à la casse).
_m07p_entete() {
  curl -s -I --max-time 10 --cacert "$_M07P_RACINE" "$1" 2>/dev/null \
    | tr -d '\r' | awk -v n="$(tr '[:upper:]' '[:lower:]' <<<"$2")" -F': *' 'tolower($1) == n { print $2 }'
}

# _m07p_serveurs_haproxy HÔTE — « section serveur état » de chaque serveur (API d'exécution).
_m07p_serveurs_haproxy() {
  remote "$1" "echo 'show stat' | sudo -n socat stdio UNIX-CONNECT:/run/haproxy/admin.sock" 2>/dev/null \
    | awk -F, 'NR > 1 && $1 !~ /^#/ && $2 != "FRONTEND" && $2 != "BACKEND" && NF > 17 { print $1, $2, $18 }'
}

# _m07p_serveur_up HÔTE SECTION SERVEUR — le serveur est UP sur ce répartiteur.
_m07p_serveur_up() {
  _m07p_serveurs_haproxy "$1" | awk -v s="$2" -v v="$3" '$1 == s && $2 == v && $3 ~ /^UP/ { ok = 1 } END { exit !ok }'
}

# --- Pannes ---------------------------------------------------------------------------------------

# _m07p_aucune_panne_active — aucune panne M07 marquée active par lab/bin/break.
_m07p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'M07-E*' 2>/dev/null)" ]]
}
