# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S14.sh — F3-S14 « Le post-mortem de la semaine » (RED publié) : présence et contenu MINIMAL du
# post-mortem docs/exploitation/post-mortems/INC-59XX.md (un incident de la semaine, S03 à S13) sur
# main de plateforme/medisphere. La qualité (raisonnement, actions pertinentes) s'auto-évalue avec le
# corrigé. Lecture seule (API GitLab).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S14 — Le post-mortem de la semaine"
require_cmd jq curl

_s14_pm="$(_f3f_fichiers_doc "^$_f3s_doc/post-mortems/INC-59(0[3-9]|1[0-3])\\.md$" | head -n 1)"
if [[ -z "$_s14_pm" ]]; then
  _ko "post-mortem $_f3s_doc/post-mortems/INC-59XX.md (incident de S03 à S13) absent de main"
else
  _ok "post-mortem présent : $_s14_pm"
  _s14_c="$(_f3s_fichier "$_s14_pm" 2>/dev/null || true)"
  _s14_a() { grep -Eiq -- "$1" <<<"$_s14_c"; }
  _s14_n() { grep -Eio -- "$1" <<<"$_s14_c" | sort -u | grep -c . || true; }
  check_cmd "résumé et justification du choix de l'incident (gravité, impact)" _s14_a 'gravit|SEV[1-4]'
  check_cmd "chronologie horodatée (au moins six instants HH:MM)" test "$(grep -Eo '\b[0-2][0-9][:h][0-5][0-9]\b' <<<"$_s14_c" | grep -c . || true)" -ge 6
  check_cmd "sources de la chronologie citées (Alertmanager, Loki, main courante)" _s14_a 'loki'
  check_cmd "impact chiffré (utilisateurs, durée, requêtes ou messages)" _s14_a 'impact'
  check_cmd "MTTA et MTTR mesurés" _s14_a 'MTTA'
  check_cmd "MTTR mesuré" _s14_a 'MTTR'
  check_cmd "causes contributives : « 5 pourquoi » (au moins trois « pourquoi »)" \
    test "$(grep -Eoi 'pourquoi' <<<"$_s14_c" | grep -c . || true)" -ge 3
  check_cmd "ce qui a bien marché" _s14_a 'bien (marché|fonctionné)|a bien marché|points positifs'
  check_cmd "actions suivies : au moins trois tickets PLAT-33xx distincts" test "$(_s14_n 'PLAT-33[0-9]{2}')" -ge 3
  check_cmd "actions datées (échéances AAAA-MM-JJ)" test "$(_s14_n '20[0-9]{2}-[01][0-9]-[0-3][0-9]')" -ge 2
  check_cmd "sans recherche de coupable : la règle est écrite" _s14_a 'coupable|blameless'
fi
