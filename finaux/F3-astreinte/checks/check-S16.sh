# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S16.sh — F3-S16 « Rapport de semaine et passation » (RED publié, recette du final) : rapport
# docs/exploitation/rapport-semaine-<AAAA-Sww>.md présent avec son contenu minimal ; étiquette
# astreinte-v1 posée sur plateforme/medisphere et contenant les livrables écrits du final (procédure,
# post-mortem, rapport) ; plus aucune injection du final ouverte sur le banc.
# Lecture seule (API GitLab, état local des pannes).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S16 — Rapport de semaine, passation et étiquette astreinte-v1"
require_cmd jq curl

_s16_r="$(_f3f_fichiers_doc "^$_f3s_doc/rapport-semaine-[0-9]{4}-S[0-5][0-9]\\.md$" | head -n 1)"
if [[ -z "$_s16_r" ]]; then
  _ko "rapport de semaine $_f3s_doc/rapport-semaine-<AAAA-Sww>.md absent de main"
else
  _ok "rapport de semaine présent : $_s16_r"
  _s16_c="$(_f3s_fichier "$_s16_r" 2>/dev/null || true)"
  _s16_a() { grep -Eiq -- "$1" <<<"$_s16_c"; }
  check_cmd "incidents de la semaine recensés (au moins huit INC-59xx distincts)" \
    test "$(grep -Eo 'INC-59[0-9]{2}' <<<"$_s16_c" | sort -u | grep -c . || true)" -ge 8
  check_cmd "MTTA et MTTR mesurés" _s16_a 'MTTA.*MTTR|MTTR.*MTTA'
  check_cmd "interruptions par service" _s16_a 'interruption'
  check_cmd "travail de fond et dette" _s16_a 'dette'
  check_cmd "points ouverts pour la personne suivante (passation)" _s16_a 'passation|points ouverts'
  check_cmd "renvoi au post-mortem de la semaine" _s16_a 'post-mortem'
fi

if _f3s_etiquette astreinte-v1; then
  _ok "étiquette astreinte-v1 posée sur $_f3s_depot"
  _s16_a_tag() { _f3s_fichier "$1" astreinte-v1 >/dev/null 2>&1; }
  check_cmd "astreinte-v1 contient la procédure de gestion d'incident" _s16_a_tag "$_f3s_doc/gestion-incidents.md"
  check_cmd "astreinte-v1 contient le rapport de semaine" _s16_a_tag "${_s16_r:-$_f3s_doc/rapport-semaine-absent.md}"
  _s16_pm_tag="$(_f3f_fichiers_doc "^$_f3s_doc/post-mortems/INC-59[0-9]{2}\\.md$" astreinte-v1 | head -n 1)"
  check_cmd "astreinte-v1 contient le post-mortem de la semaine" test -n "$_s16_pm_tag"
else
  _ko "étiquette astreinte-v1 absente de $_f3s_depot"
fi

_s16_ouvertes() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" f
  for f in "$d"/F3-S*; do [[ -e "$f" ]] && return 1; done
  return 0
}
check_cmd "aucune injection du final F3 encore ouverte sur le banc (lab/bin/break F3 <XX> --annuler après chaque incident)" _s16_ouvertes
