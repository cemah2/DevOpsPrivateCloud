# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S02.sh — F7-S02 « Les exigences non fonctionnelles, chiffrées » (RED publié) : présence et
# contenu minimal de docs/capstone/exigences.md (exigences NF-nn liées au cahier des charges, budget
# d'erreur, capacité cible calculée, RTO/RPO, traçabilité). Lecture seule (GitLab ; cahier des charges
# lu localement). La justesse des valeurs se juge avec le corrigé.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S02 — Les exigences non fonctionnelles, chiffrées"
require_cmd curl jq

_f7c_charger exigences.md
_f7_s02="$(_f7c_doc exigences.md)"

check_cmd "exigences.md présent sur main ($_f7c_doc_dir/)" _f7c_doc_present exigences.md
if [[ -z "$_f7_s02" ]]; then
  skip "contenu des exigences" "document absent"
else
  check_cmd "au moins $_f7c_min_exigences exigences NF-nn ($(_f7c_nb_ids "$_f7_s02" "$_F7C_RE_NF") trouvées)" \
    _f7c_doc_nb_ids_min exigences.md "$_F7C_RE_NF" "$_f7c_min_exigences"
  check_cmd "chaque exigence NF-nn est liée à une exigence du cahier des charges (même ligne)" \
    _f7c_part_liees_min "$_f7_s02" "$_F7C_RE_NF" "$_F7C_RE_CDC" 0.9
  check_cmd "disponibilité : 99,9 % et budget d'erreur mensuel chiffré en minutes (≈ 40 à 45 min)" \
    _f7c_doc_contient exigences.md '99[,.]9 ?%' '(^|[^0-9])4[0-5]([,.][0-9]+)?[[:space:]]*min'
  check_cmd "disponibilité : point de mesure et méthode écrits (sonde, requête, mesure)" \
    _f7c_doc_contient exigences.md 'point de mesure' 'sonde|synth(é|e)tique|blackbox' 'budget'
  _f7_s02_cap="$(_f7c_max_nombre_avant "$_f7_s02" 'req(u(ê|e)tes)?[[:space:]]*(/|par)[[:space:]]*s')"
  _f7_s02_cap_ok() { awk -v c="$_f7_s02_cap" 'BEGIN { exit !(c >= 180) }'; }
  check_cmd "capacité cible chiffrée au-delà de la pointe actuelle (croissance et saisonnalité : max trouvé ${_f7_s02_cap} req/s)" \
    _f7_s02_cap_ok
  check_cmd "capacité : le calcul cite la croissance annuelle et la campagne d'octobre" \
    _f7c_doc_contient exigences.md 'croissance|1[,.]06' 'octobre|vaccination|saisonn'
  check_cmd "volumes de données à cinq ans chiffrés (Go, To)" \
    _f7c_doc_contient exigences.md '(5|cinq) ans' '[0-9][[:space:]]*To' '[0-9][[:space:]]*Go'
  check_cmd "reprise : RTO 4 h et RPO 15 min définis et rapprochés de la mesure du F5" \
    _f7c_doc_contient exigences.md 'RTO' 'RPO' '4[[:space:]]*h' '15[[:space:]]*min' 'F5|exercice'
  _f7_s02_part="$(_f7c_part_cdc_citee "$_f7_s02" ENF ESC || true)"
  _f7_s02_trace_ok() { awk -v p="${_f7_s02_part:-0}" -v m="$_f7c_tracabilite_min" 'BEGIN { exit !(p >= m) }'; }
  check_cmd "traçabilité : ${_f7_s02_part:-0} des exigences ENF et ESC du cahier des charges reprises (minimum $_f7c_tracabilite_min)" \
    _f7_s02_trace_ok
fi
