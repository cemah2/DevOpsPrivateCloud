# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S07.sh — F4-S07 « Monter Ceph sous charge ». Deux issues, selon l'en-tête « variante » de CHG-3407 :
#   ceph-orch : tous les démons dans une même version, postérieure à la référence d'avant F4, et le code
#               (ceph_image de plateforme/ansible) la décrit ;
#   systeme   : les trois hôtes ont redémarré pendant la fenêtre et n'ont plus de mise à jour en attente.
# Dans les deux cas : HEALTH_OK, aucun drapeau de maintenance resté posé, aucune mise à jour en cours,
# autoscaler actif, mesure conforme, charge présente, RB-343. Lecture seule (commandes ceph de lecture
# sur l'hôte _admin, comme les checks du M08).
#
# Variables : WB_CEPH_ADMIN (défaut ceph01), WB_F4_CEPH_REFERENCE (défaut 20.2.4).

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S07 — Monter Ceph sous charge"
require_cmd curl jq ssh

_f4_s07_admin="${WB_CEPH_ADMIN:-ceph01}"
_f4_s07_ref="${WB_F4_CEPH_REFERENCE:-20.2.4}"
_f4_s07_noeuds=(ceph01 ceph02 ceph03)

_f4_s07_ceph() {
  local s
  s="$(remote "$_f4_s07_admin" "if command -v ceph >/dev/null 2>&1; then sudo -n ceph $1 --format json; else sudo -n cephadm shell -- ceph $1 --format json; fi" 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}
_f4_s07_sante="$(_f4_s07_ceph 'health')"
_f4_s07_versions="$(_f4_s07_ceph 'versions')"
_f4_s07_osd="$(_f4_s07_ceph 'osd dump')"
_f4_s07_pools="$(_f4_s07_ceph 'osd pool ls detail')"
_f4_s07_upgrade="$(_f4_s07_ceph 'orch upgrade status')"

_f4_s07_jq() { [[ "$1" != null ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

title "Cluster ceph-par1"
check_cmd "ceph-par1 en HEALTH_OK" _f4_s07_jq "$_f4_s07_sante" '.status == "HEALTH_OK"'
check_cmd "aucun drapeau de maintenance resté posé (noout, norebalance, nobackfill, norecover, pause)" _f4_s07_jq "$_f4_s07_osd" \
  '(.flags // "") | split(",") | map(select(test("^(noout|norebalance|nobackfill|norecover|pause|noup|nodown)$"))) | length == 0'
check_cmd "aucune mise à jour de l'orchestrateur en cours ou en pause" _f4_s07_jq "$_f4_s07_upgrade" \
  '(.in_progress // false) == false and ((.is_paused // false) == false)'
check_cmd "autoscaler des PG actif sur tous les pools" _f4_s07_jq "$_f4_s07_pools" 'length > 0 and all(.[]; .pg_autoscale_mode == "on")'

_f4_s07_variante="$(_f4m_fiche_cle CHG-3407 variante 2>/dev/null || true)"
check_cmd "CHG-3407 : variante déclarée dans l'en-tête (ceph-orch ou systeme)" bash -c '[[ "$1" == ceph-orch || "$1" == systeme ]]' _ "$_f4_s07_variante"
_f4m_mesurer CHG-3407 || true

if [[ "$_f4_s07_variante" == ceph-orch ]]; then
  title "Issue « ceph-orch » : nouvelle corrective"
  _f4_s07_v="$(jq -r '(.overall // {}) | keys[0] // empty' <<<"$_f4_s07_versions" 2>/dev/null | awk '{print $3}')" || _f4_s07_v=""
  check_cmd "ceph versions : une seule version pour tous les démons" _f4_s07_jq "$_f4_s07_versions" '(.overall // {}) | keys | length == 1'
  check_cmd "version ${_f4_s07_v:-?} postérieure à la référence $_f4_s07_ref" _f4m_version_sup "${_f4_s07_v:-}" "$_f4_s07_ref"
  check_cmd "plateforme/ansible (main) : l'image quay.io/ceph/ceph:v${_f4_s07_v:-?} est décrite" bash -c \
    '[[ -n "$1" ]] && grep -q . <<<"$2"' _ "$_f4_s07_v" \
    "$(gitlab_api "projects/plateforme%2Fansible/search?scope=blobs&search=$(_f4m_enc "quay.io/ceph/ceph:v${_f4_s07_v:-x}")&ref=main" 2>/dev/null | jq -r '.[]?.path' 2>/dev/null || true)"
elif [[ "$_f4_s07_variante" == systeme ]]; then
  title "Issue « systeme » : mise à jour en roulement des hôtes"
  _f4_s07_d0="$(_f4m_epoch "$_F4M_M_DEBUT" || echo 0)"
  _f4_s07_d1="$(_f4m_epoch "$_F4M_M_FIN" || echo 0)"
  for _f4_s07_h in "${_f4_s07_noeuds[@]}"; do
    _f4_s07_boot="$(remote "$_f4_s07_h" "awk '/^btime/ {print \$2}' /proc/stat" 2>/dev/null || true)"
    check_cmd "$_f4_s07_h : redémarré pendant la fenêtre de CHG-3407" bash -c \
      '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= $2 && $1 <= $3 && $2 > 0 ))' _ "${_f4_s07_boot:-x}" "$_f4_s07_d0" "$_f4_s07_d1"
    _f4_s07_rc=0
    remote "$_f4_s07_h" 'sudo -n dnf -q check-update >/dev/null 2>&1' || _f4_s07_rc=$?
    if ((_f4_s07_rc == 0)); then
      _ok "$_f4_s07_h : aucune mise à jour du système en attente"
    elif ((_f4_s07_rc == 100)); then
      _ko "$_f4_s07_h : des mises à jour du système sont en attente"
    else
      skip "$_f4_s07_h : mises à jour en attente" "dnf check-update n'a pas répondu (dépôts injoignables ?)"
    fi
  done
fi

title "Mesure et traces"
_f4m_controles_mesure CHG-3407
if [[ -n "$_F4M_M_DEBUT" && -n "$_F4M_M_FIN" ]]; then
  check_cmd "CHG-3407 : la charge k6 de la sonde tournait pendant la fenêtre" _f4m_charge_active "$_F4M_M_DEBUT" "$_F4M_M_FIN"
fi
check_cmd "CHG-3407 : RBD, RGW, ok-to-stop et retour arrière écrits" _f4m_fiche_contient CHG-3407 'rbd' 'rgw' 'ok-to-stop|noout' 'retour arri'
check_cmd "RB-343 publié : Ceph sous charge" _f4m_doc runbooks '^RB-343' 'ceph' 'sonde|continuit' 'health_ok'
