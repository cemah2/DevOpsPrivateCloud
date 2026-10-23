# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S07.sh — F3-S07 « Mardi soir : incident chronométré » : le service touché par la panne tirée est
# rétabli, la santé du lab est verte, et la main courante montre un incident tenu dans les 45 min avec
# un message d'état au moins toutes les 15 min. Lecture seule.

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S07 — Incident chronométré du mardi soir"
require_cmd kubectl jq curl ssh

_f3d_s07_rc=0
_f3d_s07_repare || _f3d_s07_rc=$?
case "$_f3d_s07_rc" in
  0) _ok "le service touché par l'incident de 21 h est rétabli" ;;
  2) _ko "aucun incident du soir connu sur ce poste (lab/bin/break F3 7 n'a pas été lancé depuis adm01 ?)" ;;
  *) _ko "le service touché par l'incident de 21 h n'est pas rétabli" ;;
esac

_f3s_sante

_f3d_s07_d="$(_f3s_duree_min INC-5907)"
if [[ "$_f3d_s07_d" =~ ^[0-9]+$ ]] && ((_f3d_s07_d <= 45)); then
  _ok "INC-5907 tenu en $_f3d_s07_d min (45 min au plus)"
elif [[ "$_f3d_s07_d" =~ ^[0-9]+$ ]]; then
  _ko "INC-5907 tenu en $_f3d_s07_d min : au-delà des 45 min du chronométré"
else
  _ko "INC-5907 : durée incalculable (entrées [ouverture] et [clôture] du même jour attendues)"
fi
_f3s_trace INC-5907 "$(_f3d_etats_attendus "$_f3d_s07_d")"
