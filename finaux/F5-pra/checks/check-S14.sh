# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S14.sh — F5-S14 « Recette pra-v1 : une reprise qui se teste » (depuis adm01) : documentation PRA
# complète sur main, alertes de retard de réplication et d'âge du témoin chargées dans le Prometheus de
# PAR2 et métrique du témoin fraîche, test de reprise trimestriel planifié (pipeline planifié) et réussi,
# PAR2 revenu en veille, étiquette pra-v1. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S14 — Recette pra-v1 : une reprise qui se teste"
require_cmd kubectl jq curl ssh

# 1. Documentation complète.
check_cmd "docs/pra/bia.md" _f5p_doc_motif . '^bia\.md$' 'RTO|impact'
check_cmd "docs/pra/objectifs.md (RTO, RPO)" _f5p_doc_motif . '^objectifs\.md$' 'RTO' 'RPO'
check_cmd "docs/pra/dependances.md" _f5p_doc_motif . '^dependances\.md$' 'kms01|openbao' 'dns'
check_cmd "ADR-0350 (site de repli)" _f5p_doc_motif adr '^ADR-0350' 'PAR2'
check_cmd "docs/pra/enveloppe.md" _f5p_doc_motif . '^enveloppe\.md$' 'shamir|parts?'
check_cmd "docs/pra/cellule-de-crise.md" _f5p_doc_motif . '^cellule-de-crise\.md$' 'Nadia|pilote'
_f5_s14_rb() { _f5p_doc_motif runbooks '^RB-350' 'PAR2' && _f5p_doc_motif runbooks '^RB-351' 'PAR1'; }
check_cmd "RB-350 et RB-351" _f5_s14_rb
check_cmd "rapport de l'exercice ($_f5e_exercice)" _f5p_doc_motif "exercices/$_f5e_exercice" '^rapport\.md$' 'RTO' 'RPO'
check_cmd "calendrier-tests.md : tests trimestriels partiels, exercice annuel, dates de 2027" \
  _f5p_doc_motif . '^calendrier-tests\.md$' 'trimest' 'annuel' '2027' 'responsable|qui'

# 2. Alertes et métrique du témoin (Prometheus de PAR2).
_f5_s14_regles() {
  local j
  j="$(curl -sf --max-time "$WB_TIMEOUT" "$_f5e_prom2/api/v1/rules?type=alert" 2>/dev/null)" || return 1
  jq -e '[.data.groups[].rules[] | .query] | (map(test("pra_temoin")) | any) and (map(test("cnpg_pg_replication_lag")) | any)' \
    >/dev/null 2>&1 <<<"$j"
}
check_cmd "Prometheus de PAR2 : alertes sur l'âge du témoin (pra_temoin…) et le retard de réplication (cnpg_pg_replication_lag)" _f5_s14_regles
_f5_s14_age() {
  local j
  j="$(curl -sf --max-time "$WB_TIMEOUT" --data-urlencode 'query=max({__name__=~".*pra_temoin_age_secondes"})' "$_f5e_prom2/api/v1/query" 2>/dev/null)" || return 1
  jq -e '(.data.result | length) > 0 and ((.data.result[0].value[1] | tonumber) < 900)' >/dev/null 2>&1 <<<"$j"
}
check_cmd "âge du témoin (…pra_temoin_age_secondes) présent et sous 15 min (la réplique de PAR2 suit PAR1)" _f5_s14_age

# 3. Test de reprise trimestriel automatisé (pipeline planifié).
_f5_s14_projet="${WB_F5_PROJET_ESSAI:-plateforme/k8s}"
_f5_s14_planifs="$(gitlab_api "projects/$(_f5p_enc "$_f5_s14_projet")/pipeline_schedules?per_page=100" 2>/dev/null || true)"
if [[ -z "$_f5_s14_planifs" ]]; then
  skip "pipeline planifié du test de reprise" "API pipeline_schedules de $_f5_s14_projet illisible avec le jeton des checks"
else
  _f5_s14_id="$(jq -r '[.[] | select(.active == true and (.description | test("pra|reprise"; "i")))][0].id // empty' <<<"$_f5_s14_planifs" 2>/dev/null || true)"
  check_cmd "$_f5_s14_projet : pipeline planifié actif du test de reprise (description « pra » ou « reprise »)" test -n "$_f5_s14_id"
  if [[ -n "$_f5_s14_id" ]]; then
    _f5_s14_dern="$(gitlab_api "projects/$(_f5p_enc "$_f5_s14_projet")/pipeline_schedules/$_f5_s14_id" 2>/dev/null | jq -r '.last_pipeline.status // empty' 2>/dev/null || true)"
    check_cmd "dernier pipeline du test de reprise réussi (statut : ${_f5_s14_dern:-aucun})" test "$_f5_s14_dern" = success
  fi
fi

# 4. PAR2 revenu en veille, étiquette.
check_cmd "k8s-par2 : plus aucun pod de l'API de MédiAgenda en marche (cluster tiède)" _f5e_kq2 \
  '[.items[] | select(.status.phase == "Running")] | length == 0' \
  pods -n "$_F5E_NS_PROD" -l 'app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
check_cmd "temoin-rpo suspendu à PAR2 (site passif)" _f5e_kq2 '.spec.suspend == true' cronjob temoin-rpo -n "$_F5E_NS_PROD"
check_cmd "étiquette pra-v1 posée sur $_f5p_projet_doc" _f5e_etiquette pra-v1
