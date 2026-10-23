# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E43.sh — M24-E43 « Astreinte : la matinée où personne ne pouvait se connecter » : tout le
# périmètre de M24-E35 à M24-E42 est sain, aucune panne n'est encore active, le post-mortem et RB-246
# sont sur main de plateforme/medisphere. Lecture seule.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E43 — Astreinte : la matinée où personne ne pouvait se connecter"
require_cmd jq curl

_m24y_e43_pm_chemin="$(_m24y_doc_trouver "$_M24P_DOC/post-mortems" 'INC-5143[^/]*\.md$')"
_m24y_e43_pm=""
[[ -n "$_m24y_e43_pm_chemin" ]] && _m24y_e43_pm="$(_m24p_doc "$_m24y_e43_pm_chemin")"
check_cmd "post-mortem sur main ($_M24P_DOC/post-mortems/*INC-5143*.md)" test -n "$_m24y_e43_pm"
check_cmd "post-mortem : chronologie, causes, détection, actions" _m24p_tous "$_m24y_e43_pm" \
  '^#+ .*chronologie' '^#+ .*causes?' '^#+ .*d[ée]tection' '^#+ .*actions'
check_cmd "post-mortem : au moins quatre heures de communication (points toutes les 30 min)" \
  _m24p_compare "$(grep -Eo '\b([01][0-9]|2[0-3])[:h][0-5][0-9]\b' <<<"$_m24y_e43_pm" | sort -u | wc -l)" '>=' 4
check_cmd "post-mortem : extraits de diagnostic (journalctl, curl, kubectl, ipa, sssctl, openssl…)" _m24d_contient "$_m24y_e43_pm" \
  'journalctl|curl |kubectl |ipa |sssctl|openssl|haproxy|psql'
check_cmd "post-mortem : aucun jeton, aucune clé privée, aucun secret recopié" _m24y_sans_jeton "$_m24y_e43_pm"
check_cmd "post-mortem : bris de glace tracés (lesquels, qui, quand, refermés) ou « aucun »" _m24d_contient "$_m24y_e43_pm" \
  '[Bb]ris de glace'

_m24y_e43_rb="$(_m24y_rb246)"
check_cmd "RB-246 (SSO indisponible) sur main" test -n "$_m24y_e43_rb"
check_cmd "RB-246 : premier diagnostic, arbre par couche, bris de glace, communication" _m24p_tous "$_m24y_e43_rb" \
  'd[ée]couverte|well-known' 'haproxy|r[ée]partiteur' 'RB-240|bris de glace' 'communication|message'
check_cmd "aucune panne M24 encore marquée active (lab/bin/break)" _m24y_aucune_panne

_m24y_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
for _m24y_e43_x in E35 E36 E37 E38 E39 E40 E41 E42; do
  if [[ -f "$_m24y_e43_checks/check-$_m24y_e43_x.sh" ]]; then
    # shellcheck disable=SC1090  # contrôles des autres exercices du palier, chargés dynamiquement
    source "$_m24y_e43_checks/check-$_m24y_e43_x.sh"
  else
    skip "contrôle M24-$_m24y_e43_x" "script check-$_m24y_e43_x.sh absent"
  fi
done
