# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E27.sh — M08-E27 « Sécuriser Ceph : chiffrement et clés »
# Lecture seule : configuration centrale et valeurs en vigueur (config get/show), spécification des
# OSD (orch ls --export), lsblk sur ceph03, santé, entités cephx (sans les clés), clé publique de
# l'orchestrateur (get-pub-key) comparée aux clés autorisées du compte cephadm (sudo -n grep).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E27 — Sécuriser Ceph : chiffrement et clés"
require_cmd jq
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "Chiffrement en transit (msgr2)"
for _m08_e27_o in ms_cluster_mode ms_service_mode ms_client_mode; do
  check_output "configuration centrale : $_m08_e27_o = secure (sans crc)" '^secure$' _m08p_config_get osd "$_m08_e27_o"
done
for _m08_e27_o in ms_mon_cluster_mode ms_mon_service_mode ms_mon_client_mode; do
  check_output "configuration centrale : $_m08_e27_o = secure (sans crc)" '^secure$' _m08p_config_get mon "$_m08_e27_o"
done
_m08_e27_osd="$(_m08p_demons osd 2>/dev/null | head -n 1 || true)"
_m08_e27_mon="$(_m08p_demons mon 2>/dev/null | head -n 1 || true)"
check_output "en vigueur dans ${_m08_e27_osd:-un OSD} : ms_cluster_mode = secure (démon redémarré)" '^secure$' \
  _m08p_config_show "${_m08_e27_osd:-osd.0}" ms_cluster_mode
check_output "en vigueur dans ${_m08_e27_osd:-un OSD} : ms_service_mode = secure" '^secure$' \
  _m08p_config_show "${_m08_e27_osd:-osd.0}" ms_service_mode
check_output "en vigueur dans ${_m08_e27_mon:-un MON} : ms_mon_service_mode = secure" '^secure$' \
  _m08p_config_show "${_m08_e27_mon:-mon.ceph01}" ms_mon_service_mode

title "Chiffrement au repos"
check_output "spécification des OSD : encrypted: true" 'encrypted: *true' _m08p_ceph 'orch ls osd --export'
check_cmd "ceph03 : trois OSD chiffrés (périphériques crypt)" _m08p_crypt ceph03 3

title "Clés cephx"
for _m08_e27_c in AUTH_INSECURE_SERVICE_KEY_TYPE AUTH_INSECURE_SERVICE_TICKETS; do
  check_cmd "contrôle $_m08_e27_c absent (ni actif ni en sourdine)" _m08p_controle_absent "$_m08_e27_c"
done
check_cmd "le nouveau type de clé cephx est accepté par les moniteurs (aes256k)" bash -c \
  'grep -q aes256k <<<"$1"' _ "$(_m08p_json 'mon dump' | jq -c '.auth_allowed_ciphers // empty' 2>/dev/null)"
check_cmd "l'identité de secours client.admin-backup n'existe plus" _m08p_entite_absente client.admin-backup
check_cmd "toute mise en sourdine a une durée et ne porte que sur les contrôles « clients » de cephx" \
  _m08p_sourdines_temporaires '^AUTH_INSECURE_(CLIENT_KEY_TYPE|KEYS_CREATABLE|KEYS_ALLOWED)$'
check_cmd "aucun contrôle de santé actif hors sourdine (ce qui reste attend une date, en sourdine temporaire)" \
  _m08p_seuls_controles '^$'

title "Clé SSH de l'orchestrateur (compte cephadm des nœuds)"
_m08_e27_cle="$(_m08p_ceph 'cephadm get-pub-key' | awk '/^(ssh|ecdsa)-/ {print $1" "$2; exit}' || true)"
check_cmd "clé publique courante de l'orchestrateur lisible" test -n "$_m08_e27_cle"
for _m08_e27_h in $(_m08p_hotes_orch 2>/dev/null || printf '%s ' "${_M08P_NOEUDS[@]}"); do
  check_ssh "$_m08_e27_h : la clé courante est la seule clé autorisée du compte cephadm" "$_m08_e27_h" \
    'k=$(sudo -n grep -Ev "^[[:space:]]*(#|$)" /var/lib/cephadm/.ssh/authorized_keys 2>/dev/null) || exit 1
     [ "$(grep -c . <<<"$k")" = 1 ] && grep -qF "'"${_m08_e27_cle:-absente}"'" <<<"$k"'
done
check_cmd "orchestrateur : aucun hôte hors ligne, en erreur ou en maintenance" \
  _m08p_jq _M08P_HOTES 'length >= 3 and all(.[]; (.status // "") == "")'
