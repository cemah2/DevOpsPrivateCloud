# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E28.sh — M05-E28 « Détecter la dérive de l'infrastructure »
# Planification quotidienne sur main (PLANIF=derive), jeton d'alerte protégé, rapport conservé
# environ 90 jours, ticket « derive » ouvert puis fermé, dernière détection planifiée conforme,
# outil utilisable sur adm01, règle de traitement écrite dans docs/socle/iac.md.
# Le contrôle ne lance PAS la détection (elle prend le verrou des états) : il lit ses traces.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E28 — Détection de dérive"
require_cmd jq curl

# _m05_e28_rapport_conserve — le dernier job de dérive planifié a des artefacts gardés ≥ 80 jours.
_m05_e28_rapport_conserve() {
  local j
  j="$(_m05p_dernier_job_planifie '^derive')" || return 1
  _m05p_artefacts_conserves "$j" 80
}

# _m05_e28_derniere_conforme — dans le dernier pipeline planifié qui contient des jobs de
#   dérive, tous ces jobs ont réussi (code 0 : conforme ; 2 et 3 donnent « failed » autorisé).
_m05_e28_derniere_conforme() {
  local ids pid j
  ids="$(gitlab_api "$_M05P_PROJET/pipelines?source=schedule&ref=main&per_page=30" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    j="$(gitlab_api "$_M05P_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -c '[.[] | select((.name | test("^derive")) and (.name | test("alerte") | not))]' 2>/dev/null)" || continue
    if jq -e 'length > 0 and all(.[]; .status == "success" or .status == "failed")' >/dev/null 2>&1 <<<"$j"; then
      jq -e 'all(.[]; .status == "success")' >/dev/null <<<"$j"
      return
    fi
  done
  return 1
}

title "Planification et secrets (GitLab)"
check_cmd "pipeline planifié actif sur main avec PLANIF=derive" _m05p_planif derive
check_cmd ".gitlab-ci.yml sur main : détection dans les pipelines planifiés" \
  _m05p_main_contient .gitlab-ci.yml 'PLANIF[[:space:]]*==[[:space:]]*"derive"'
check_cmd "DERIVE_TOKEN : protégé et masqué" \
  _m05p_variable_ok DERIVE_TOKEN '.protected and (.masked or (.masked_and_hidden // false))'
check_cmd "registre des secrets : DERIVE_TOKEN inscrit" \
  _m05p_doc_contient "$_M05P_DOC/registre-secrets.md" 'DERIVE_TOKEN'

title "Détections"
check_cmd "une détection planifiée a produit un rapport conservé environ 90 jours" _m05_e28_rapport_conserve
check_cmd "un ticket « derive » a été ouvert par une détection" \
  _m05p_api_ok "$_M05P_PROJET/issues?labels=derive&state=all&per_page=20" 'length > 0'
check_cmd "un ticket « derive » a été fermé après résolution" \
  _m05p_api_ok "$_M05P_PROJET/issues?labels=derive&state=closed&per_page=20" 'length > 0'
check_cmd "aucun ticket « derive » ouvert" \
  _m05p_api_ok "$_M05P_PROJET/issues?labels=derive&state=opened&per_page=20" 'length == 0'
check_cmd "la dernière détection planifiée est conforme" _m05_e28_derniere_conforme

title "Poste et documentation"
check_cmd "outil de détection exécutable dans le clone local (outils/)" \
  bash -c 'for f in "$1"/outils/*; do [ -x "$f" ] && grep -q -- "-refresh-only" "$f" && exit 0; done; exit 1' _ "$_M05P_INFRA"
check_cmd "docs/socle/iac.md : traitement d'une dérive (voie, décideur, délai)" \
  _m05p_doc_contient "$_M05P_DOC/iac.md" 'dérive' 'refresh-only|écart' 'délai'
