# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M25-E24 « Grappe Raft à trois nœuds et VIP » : le nom du service mène à la VIP ;
# chaque nœud répond, descellé ; un seul actif (200), les autres en attente (429) ; la VIP est sur
# l'actif et nulle part ailleurs ; trois électeurs Raft, autopilot sain et réglé ; certificats à
# deux noms ; keepalived VRID 120 ; mesures des bascules écrites.
# À lancer depuis adm01. Lecture seule : sys/health et sys/leader sans jeton, AppRole wb-checks
# (sys/storage/raft/configuration, autopilot : chemins ajoutés à la politique au M25-E24), SSH en
# consultation, openssl s_client.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E24 — Grappe Raft à trois nœuds et VIP"
require_cmd curl jq dig openssl
_m25p_connexion

check_dns "$_M25P_SERVICE résout en la VIP $_M25P_VIP" "$_M25P_SERVICE" A "^${_M25P_VIP//./\\.}$"

for _m25_e24_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25_e24_n : répond et est descellé (sys/health)" \
    _m25p_jq "$(_m25p_sante "$_m25_e24_n")" '.initialized == true and .sealed == false'
done

_m25_e24_actifs="$(_m25p_actifs)"
check_output "un seul nœud actif (200), les autres en attente (429) — actif : ${_m25_e24_actifs//$'\n'/ }" '^1$' \
  bash -c 'grep -c . <<<"$1"' _ "$_m25_e24_actifs"
_m25_e24_attente() {
  local n c k=0
  for n in "${_M25P_NOEUDS[@]}"; do
    c="$(_m25p_code "$n")"
    [[ "$c" == 429 ]] && k=$((k + 1))
  done
  ((k == ${#_M25P_NOEUDS[@]} - 1))
}
check_cmd "les ${#_M25P_NOEUDS[@]} - 1 autres nœuds répondent 429 (en attente, descellés)" _m25_e24_attente

# Par la VIP, sys/leader doit répondre « je suis l'actif » : la VIP est bien sur le nœud actif.
check_cmd "sys/leader lu par la VIP : le nœud qui la porte est l'actif (is_self)" \
  _m25p_jq "$(curl -s --max-time "$WB_TIMEOUT" "https://$_M25P_SERVICE:$_M25P_PORT/v1/sys/leader" 2>/dev/null || echo null)" '.is_self == true'

_m25_e24_vip() {
  local n porteurs=""
  for n in "${_M25P_NOEUDS[@]}"; do
    _m25p_ssh_sortie "$n" "ip -4 -o addr show to $_M25P_VIP/32" | grep -q "$_M25P_VIP" && porteurs="$porteurs $n"
  done
  [[ "$(wc -w <<<"$porteurs")" -eq 1 && " $porteurs " == *" ${_m25_e24_actifs%%$'\n'*} "* ]]
}
check_cmd "la VIP $_M25P_VIP est portée par un seul nœud, l'actif" _m25_e24_vip

for _m25_e24_n in "${_M25P_NOEUDS[@]}"; do
  check_ssh "$_m25_e24_n : keepalived actif, instance VRID 120" "$_m25_e24_n" \
    'systemctl is-active --quiet keepalived && sudo -n grep -Eq "virtual_router_id[[:space:]]+120" /etc/keepalived/keepalived.conf'
done

_m25_e24_raft="$(_m25p_bao sys/storage/raft/configuration)"
if [[ "$_m25_e24_raft" == null ]]; then
  check_cmd "configuration Raft lisible par l'AppRole wb-checks (sys/storage/raft/configuration ajouté à la politique ?)" false
else
  check_cmd "trois pairs Raft, tous électeurs, un leader" _m25p_jq "$_m25_e24_raft" \
    '.data.config.servers | (length == 3) and all(.voter == true) and (map(select(.leader)) | length == 1)'
  check_cmd "les pairs sont vault01, vault02 et vault03 (node_id = nom de l'hôte)" _m25p_jq "$_m25_e24_raft" \
    '[.data.config.servers[].node_id] | sort == ["vault01", "vault02", "vault03"]'
fi
check_cmd "autopilot sain, tolérance d'au moins une panne" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/state)" '.data.healthy == true and .data.failure_tolerance >= 1'
check_cmd "autopilot : cleanup_dead_servers activé, min_quorum à 3" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/configuration)" '.data.cleanup_dead_servers == true and .data.min_quorum == 3'

# Certificats : chaque nœud présente un certificat valide (racine du magasin système) pour le nom du
# service ET pour son propre nom.
_m25_e24_cert() {
  local n="$1" pem
  pem="$(openssl s_client -connect "$n.$_M25P_DOMAINE:$_M25P_PORT" -servername "$_M25P_SERVICE" -verify_return_error \
    </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -checkhost "$_M25P_SERVICE" <<<"$pem" 2>/dev/null | grep -q 'does match' \
    && openssl x509 -noout -checkhost "$n.$_M25P_DOMAINE" <<<"$pem" 2>/dev/null | grep -q 'does match'
}
for _m25_e24_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25_e24_n : certificat vérifié, valable pour $_M25P_SERVICE et $_m25_e24_n.$_M25P_DOMAINE" _m25_e24_cert "$_m25_e24_n"
done

_m25_e24_mesures() {
  local f="$HOME/m25/e24/mesures.md" n
  [[ -r "$f" ]] || return 1
  n="$(grep -Eio '[0-9]+([.,][0-9]+)? ?(ms|s|secondes?)\b' "$f" | wc -l)"
  ((n >= 3)) && grep -Eqi 'step-down|passage de t' "$f" && grep -Eqi 'brutal|qm stop' "$f"
}
check_cmd "mesures des bascules (~/m25/e24/mesures.md) : trois épreuves et leurs durées" _m25_e24_mesures
