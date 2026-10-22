# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M26-E34 « Audit de conformité en temps limité » (CHRONO, à lancer à la fin)
# À lancer depuis adm01. Lecture seule : rapport le plus récent de docs/securite/durcissement/rapports/
# sur main de plateforme/medisphere (date du nom de fichier, sections, actions datées), score CIS
# moyen du moment (Thanos Query) comparé aux scores cités.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E34 — Audit de conformité en temps limité"
require_cmd jq curl

_m26_e34_f="$(_m26p_arbre "$_M26P_DOC" docs/securite/durcissement/rapports \
  | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}-audit-conformite[^/]*\.md$' | sort | tail -n 1 || true)"
if [[ -z "$_m26_e34_f" ]]; then
  check_cmd "rapport docs/securite/durcissement/rapports/AAAA-MM-JJ-audit-conformite.md sur main de $_M26P_DOC" false
  return 0
fi
check_cmd "rapport présent : $_m26_e34_f" true
_m26_e34_date="$(grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"${_m26_e34_f##*/}" | head -n 1)"
_m26_e34_age="$(( ( $(date +%s) - $(date -d "$_m26_e34_date" +%s 2>/dev/null || echo 0) ) / 86400 ))"
check_output "rapport daté de moins de 7 jours ($_m26_e34_date)" '^[0-7]$' echo "$_m26_e34_age"
_m26_e34_txt="$(_m26p_fichier "$_M26P_DOC" "$_m26_e34_f" || true)"

_m26_e34_section() { grep -Eqi "^#{1,4} .*($1)" <<<"$_m26_e34_txt"; }
check_cmd "section « Périmètre et méthode »" _m26_e34_section 'p(é|e)rim(è|e)tre'
check_cmd "section « Synthèse »" _m26_e34_section 'synth(è|e)se'
check_cmd "section « Écarts »" _m26_e34_section '(É|é|E|e)carts'
check_cmd "section « Exceptions »" _m26_e34_section 'exceptions'
check_cmd "section « Plan de remédiation »" _m26_e34_section 'rem(é|e)diation'
check_cmd "section « Retour d'expérience »" _m26_e34_section "retour d.{1,3}exp(é|e)rience"
# Actions datées : lignes de la section du plan qui contiennent une date (AAAA-MM-JJ ou JJ/MM/AAAA).
_m26_e34_plan="$(awk '{ l = tolower($0) } l ~ /^#+ .*rem(é|e)diation/ { p = 1; next } /^#+ / { p = 0 } p' <<<"$_m26_e34_txt")"
_m26_e34_actions="$(grep -cE '([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2}/[0-9]{2}/[0-9]{4})' <<<"$_m26_e34_plan" || true)"
check_output "au moins cinq actions datées dans le plan ($_m26_e34_actions)" '^([5-9]|[1-9][0-9]+)$' echo "$_m26_e34_actions"
# Cohérence : un score CIS cité à 5 points près du score moyen du moment.
_m26_e34_moy="$(_m26p_valeur 'avg(medisphere_conformite_score{referentiel="cis_l1_serveur"})')"
if [[ -z "$_m26_e34_moy" ]]; then
  skip "cohérence du score CIS cité" "pas de score dans Thanos Query"
else
  _m26_e34_coherent() {
    grep -Ei 'cis' <<<"$_m26_e34_txt" | grep -Eo '[0-9]{1,3}([.,][0-9]+)?' | tr ',' '.' \
      | awk -v m="$_m26_e34_moy" '$1 >= m - 5 && $1 <= m + 5 { ok = 1 } END { exit !ok }'
  }
  check_cmd "un score CIS cité correspond au score moyen du moment (${_m26_e34_moy%%.*} ± 5)" _m26_e34_coherent
fi
