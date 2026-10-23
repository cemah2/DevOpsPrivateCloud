# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S01.sh — F6-S01 « Périmètre, exigences et déclaration d'applicabilité » (RED publié) : présence et
# contenu minimal de docs/conformite/perimetre.md et soa.md (les 93 mesures de l'annexe A, chacune avec
# une décision ; chaque exclusion justifiée ; les exigences HDS). Lecture seule (GitLab). La qualité du
# raisonnement se juge avec le corrigé.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S01 — Périmètre, exigences et déclaration d'applicabilité"
require_cmd curl jq awk

_f6_s01_p="$(_f6c_contenu perimetre.md)"
_f6_s01_s="$(_f6c_contenu soa.md)"

check_cmd "perimetre.md (main) : périmètre du SMSI, sites PAR1 et PAR2, services hébergés" \
  _f6c_contient "$_f6_s01_p" 'PAR1' 'PAR2' 'M(é|e)diAgenda' 'p(é|e)rim(è|e)tre'
check_cmd "perimetre.md : les six activités HDS, chacune dite exercée ou non" \
  _f6c_contient "$_f6_s01_p" 'activit(é|e)' 'site' 'mat(é|e)riel' 'virtuel' 'plateforme' 'administration|exploitation' 'sauvegarde'
check_cmd "perimetre.md : exclusions du périmètre et interfaces (sous-traitants, clients)" \
  _f6c_contient "$_f6_s01_p" 'exclu|hors p(é|e)rim(è|e)tre' 'sous-traitan|fournisseur|colocation'

_f6_s01_manquantes() { [[ -n "$_f6_s01_s" ]] && [[ -z "$(_f6c_soa_manquantes "$_f6_s01_s")" ]]; }
_f6_s01_n="$( [[ -n "$_f6_s01_s" ]] && _f6c_soa_manquantes "$_f6_s01_s" | wc -l || echo 93)"
check_cmd "soa.md : les 93 mesures de l'annexe A ont une décision (Oui/Non) et chaque exclusion une justification (manquantes : ${_f6_s01_n// /})" \
  _f6_s01_manquantes
check_cmd "soa.md : exigences HDS (localisation dans l'EEE, transferts, contrat, activités exercées)" \
  _f6c_contient "$_f6_s01_s" 'HDS' 'EEE|Espace (é|e)conomique europ(é|e)en' 'transfert' 'contrat'
check_cmd "soa.md : version du référentiel et date de la déclaration" \
  _f6c_contient "$_f6_s01_s" '27001:2022' 'version|r(é|e)vision' '20[0-9]{2}-[0-9]{2}-[0-9]{2}'
