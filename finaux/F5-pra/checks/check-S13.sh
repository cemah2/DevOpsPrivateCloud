# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions entre apostrophes passées à bash -c
# check-S13.sh — F5-S13 « Le rapport d'exercice PRA » (RED publié) : présence et contenu minimal de
# docs/pra/exercices/<exercice>/rapport.md (en-tête de mesures, objectifs, chronologie, écarts, actions
# PLAT-35xx) et cohérence des RTO déclarés avec les mesures exportées de la sonde
# (docs/pra/mesures/<exercice>/sonde-mesures.csv). Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S13 — Le rapport d'exercice PRA"
require_cmd jq curl

_f5_s13_dir="docs/pra/exercices/$_f5e_exercice"
_f5_s13_rapport="$(_f5e_fichier "$_f5e_depot_doc" "$_f5_s13_dir/rapport.md" 2>/dev/null || true)"
check_cmd "$_f5_s13_dir/rapport.md publié sur main" test -n "$_f5_s13_rapport"
_f5_s13_cle() { sed -n '1,/^---$/{/^---$/!p}' <<<"${_f5_s13_rapport#---$'\n'}" | sed -n "s/^$1:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" | head -n1; }
for _f5_k in t0 rto-mediagenda-min rto-medidoc-min rto-rdv-min rpo-mediagenda-min coupure-retour-min; do
  check_cmd "en-tête du rapport : « $_f5_k » renseigné" test -n "$(_f5_s13_cle "$_f5_k")"
done
for _f5_m in 'objectif' 'chronolog' '(é|e)cart' 'PLAT-35[0-9][0-9]' 'le(c|ç)on|retenir' 'RPO' 'RTO'; do
  check_cmd "rapport : contient « $_f5_m »" grep -Eqi -- "$_f5_m" <<<"$_f5_s13_rapport"
done

# Cohérence avec la sonde : RTO recalculé sur les mesures exportées (± 2 min).
_F5E_CSV="$(_f5e_fichier "$_f5e_depot_doc" "docs/pra/mesures/$_f5e_exercice/sonde-mesures.csv" 2>/dev/null || true)"
_f5_s13_t0="$(date -d "$(_f5_s13_cle t0)" +%s 2>/dev/null || true)"
if [[ -z "$_F5E_CSV" || -z "$_f5_s13_t0" ]]; then
  check_cmd "mesures exportées (docs/pra/mesures/$_f5e_exercice/sonde-mesures.csv) et T0 lisibles" false
else
  for _f5_app in mediagenda medidoc rdv; do
    _f5_dec="$(_f5_s13_cle "rto-$_f5_app-min")"
    _f5_cal="$(_f5e_rto "$_f5_app.medisphere.internal" "$_f5_s13_t0" || true)"
    check_cmd "RTO $_f5_app déclaré (${_f5_dec:-?} min) = mesure recalculée (${_f5_cal:-?} min) à 2 min près" \
      bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( ($1 - $2) * ($1 - $2) <= 4 ))' _ "$_f5_dec" "$_f5_cal"
  done
fi
