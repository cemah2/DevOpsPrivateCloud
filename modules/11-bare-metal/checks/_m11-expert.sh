# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# _m11-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du
# module 11 (check-E19 à check-E25). Charge _m11-production.sh. Sourcé, jamais lancé seul.
# Lecture seule : configuration lue par sudo -n (cat, grep, nginx -T, kea-dhcp4 -t), sondes TFTP et
# HTTPS, API de MAAS en GET (signée OAuth, clé lue dans un fichier), pveum/qm en lecture sur pve01.
# Préfixe _m11x_.

# shellcheck source=_m11-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-production.sh"

_m11x_maas_url="${WB_MAAS_URL:-http://10.10.60.11:5240/MAAS}"
_m11x_maas_cle="${WB_MAAS_KEY_FILE:-$_m11p_cfg/maas-api.key}"

# _m11x_maas GET CHEMIN — corps de la réponse si 2xx (API 2.0 de MAAS, OAuth 1.0 PLAINTEXT ;
# en-tête écrit dans un fichier temporaire 600, jamais en argument).
_m11x_maas() {
  local chemin="$2" ck tk ts e sortie code
  [[ -r "$_m11x_maas_cle" ]] || return 1
  IFS=: read -r ck tk ts <"$_m11x_maas_cle"
  e="$(mktemp)"
  chmod 600 "$e"
  printf 'Authorization: OAuth oauth_version="1.0", oauth_signature_method="PLAINTEXT", oauth_consumer_key="%s", oauth_token="%s", oauth_signature="&%s", oauth_nonce="%s", oauth_timestamp="%s"\n' \
    "$ck" "$tk" "$ts" "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" "$(date +%s)" >"$e"
  sortie="$(curl -sS --max-time 30 -X "$1" -H @"$e" -w '\n%{http_code}' "$_m11x_maas_url/api/2.0/$chemin" 2>/dev/null)" || true
  rm -f -- "$e"
  code="$(tail -n 1 <<<"$sortie")"
  [[ "$code" =~ ^2 ]] || return 1
  sed '$d' <<<"$sortie"
}

# _m11x_maas_bm — lignes « system_id nom » des machines bm01-bm04 connues de MAAS.
_m11x_maas_bm() {
  _m11x_maas GET "machines/" | jq -r '.[] | select(.hostname | test("^bm0[1-4]$")) | "\(.system_id) \(.hostname)"' 2>/dev/null
}

# _m11x_kea_conf HÔTE — configuration de Kea de l'hôte (lecture par sudo -n).
_m11x_kea_conf() {
  remote "$1" 'sudo -n cat /etc/kea/kea-dhcp4.conf' 2>/dev/null
}

# _m11x_relais_vlan60 — au moins une passerelle relaie le VLAN 60 (ligne active, dnsmasq actif).
_m11x_relais_vlan60() {
  local h
  for h in gw01 gw02; do
    # shellcheck disable=SC2016
    if remote "$h" 'systemctl is-active -q dnsmasq && sudo -n grep -Eqs "^[[:space:]]*dhcp-relay=10\.10\.60\." /etc/dnsmasq.d/*.conf /etc/dnsmasq.conf' >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# _m11x_relais_vlan99 — le relais du VLAN 99 est toujours en place sur au moins une passerelle.
_m11x_relais_vlan99() {
  local h
  for h in gw01 gw02; do
    # shellcheck disable=SC2016
    if remote "$h" 'systemctl is-active -q dnsmasq && sudo -n grep -Eqs "^[[:space:]]*dhcp-relay=10\.10\.99\." /etc/dnsmasq.d/*.conf /etc/dnsmasq.conf' >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# _m11x_scripts_mac — chemins (URL) des scripts par MAC servis par pxe01.
_m11x_scripts_mac() {
  local r
  r="$(_m11p_racine_nginx)"
  [[ -n "$r" ]] || return 1
  remote pxe01 "ls '$r'/ipxe/ 2>/dev/null" 2>/dev/null | grep -E '^mac-.*\.ipxe$' | sed 's|^|/ipxe/|'
}
