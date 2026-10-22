# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M20-E24 « RBAC d'Argo CD et projets par équipe » (SEC-2124)
# À lancer depuis adm01. Lecture seule : argocd-rbac-cm et AppProjects (wb-checks), évaluation HORS
# LIGNE de la politique en vigueur par la CLI argocd, API d'Argo CD avec le jeton ci-lecture (GET),
# GitLab (fichiers sur main, dernier pipeline de plateforme/k8s).

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E24 — RBAC d'Argo CD et projets par équipe"
require_cmd kubectl jq curl argocd
_m20p_init_tmp
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

title "Politique en vigueur (argocd-rbac-cm)"
_m20_e24_cm="$(_m20p_cm argocd-rbac-cm)"
_m20_e24_csv="$(jq -r '[.data // {} | to_entries[] | select(.key | test("^policy(\\..+)?\\.csv$")) | .value] | join("\n")' \
  <<<"$_m20_e24_cm" 2>/dev/null || true)"
check_cmd "argocd-rbac-cm est lisible" _m20p_jq "$_m20_e24_cm" '.metadata.name == "argocd-rbac-cm"'
check_cmd "policy.default est vide (aucun droit par défaut)" _m20p_jq "$_m20_e24_cm" \
  '((.data["policy.default"] // "") | gsub("\\s"; "")) == ""'
for _m20_e24_r in role:plateforme-admin role:mediagenda-equipe role:lecture; do
  check_output "le rôle $_m20_e24_r est défini (lignes p ou g)" "^[pg], *${_m20_e24_r}," \
    printf '%s\n' "$_m20_e24_csv"
done
# Sujets liés (g) à role:admin ou role:plateforme-admin, hors héritage role:plateforme-admin → role:admin.
_m20_e24_admins="$(awk -F', *' '/^g,/ && ($3 ~ /^role:(admin|plateforme-admin)[[:space:]]*$/) && $2 != "role:plateforme-admin" {print $2}' \
  <<<"$_m20_e24_csv" | sort -u | tr '\n' ' ' || true)"
if [[ -n "$_M20P_MOI_ARGO" ]]; then
  check_output "seuls <MOI-ARGO> ($_M20P_MOI_ARGO) et karim-benali sont administrateurs (trouvés : ${_m20_e24_admins:-aucun})" '^ok$' \
    bash -c 'for s in $1; do [[ "$s" == "$2" || "$s" == karim-benali ]] || exit 1; done; echo ok' _ \
    "$_m20_e24_admins" "$_M20P_MOI_ARGO"
else
  skip "administrateurs limités à <MOI-ARGO> et karim-benali" "WB_MOI non défini dans lab/lab.env"
fi

title "Évaluation de la politique en vigueur (argocd admin settings rbac can, hors ligne)"
_m20_e24_f="$(_m20p_rbac_fichier || true)"
if [[ -n "$_m20_e24_f" ]]; then
  _m20_e24_cas() { # ATTENDU (Yes|No) DESCRIPTION SUJET ACTION RESSOURCE OBJET
    local attendu="$1" desc="$2"
    shift 2
    check_output "$desc" "^${attendu}\$" _m20p_rbac_peut "$_m20_e24_f" "$@"
  }
  _m20_e24_cas Yes "julien-petit synchronise mediagenda-recette" julien-petit sync applications mediagenda/mediagenda-recette
  _m20_e24_cas Yes "julien-petit lit mediagenda-prod" julien-petit get applications mediagenda/mediagenda-prod
  _m20_e24_cas No "julien-petit ne synchronise pas mediagenda-prod" julien-petit sync applications mediagenda/mediagenda-prod
  _m20_e24_cas No "julien-petit ne synchronise pas medidoc-dev" julien-petit sync applications medidoc/medidoc-dev
  _m20_e24_cas No "julien-petit ne supprime pas mediagenda-dev" julien-petit delete applications mediagenda/mediagenda-dev
  _m20_e24_cas No "julien-petit n'a pas de terminal (exec)" julien-petit create exec mediagenda/mediagenda-dev
  _m20_e24_cas No "julien-petit ne fait pas d'override" julien-petit override applications mediagenda/mediagenda-recette
  _m20_e24_cas Yes "nadia-roussel lit mediagenda-prod" nadia-roussel get applications mediagenda/mediagenda-prod
  _m20_e24_cas No "nadia-roussel ne synchronise pas mediagenda-prod" nadia-roussel sync applications mediagenda/mediagenda-prod
  _m20_e24_cas No "nadia-roussel ne lit pas les journaux des pods de production" nadia-roussel get logs mediagenda/mediagenda-prod
  _m20_e24_cas No "un compte inconnu n'a aucun droit" compte-inconnu-wb get applications mediagenda/mediagenda-dev
else
  check_cmd "évaluation de la politique (argocd-rbac-cm illisible)" false
fi

title "Jeton ci-lecture (API d'Argo CD)"
_m20_e24_api_apps() { _m20p_argocd_api applications | jq -e '(.items | length) > 0' >/dev/null; }
_m20_e24_api_clusters() { _m20p_argocd_api clusters | jq -e '(.items | length) > 0' >/dev/null; }
_m20_e24_api_cani() { _m20p_argocd_api account/can-i/applications/sync/mediagenda/mediagenda-prod | jq -r '.value'; }
check_cmd "ci-lecture lit les Applications" _m20_e24_api_apps
check_cmd "ci-lecture lit les clusters" _m20_e24_api_clusters
check_output "l'API répond « no » à ci-lecture pour synchroniser mediagenda-prod" '^no$' _m20_e24_api_cani

title "Rôles de projet"
for _m20_e24_p in mediagenda medidoc; do
  check_cmd "AppProject $_m20_e24_p : rôle « equipe » avec au moins un groupe" _m20p_jq "$(_m20p_projet "$_m20_e24_p")" \
    "any(.spec.roles[]?; .name == \"equipe\" and ((.groups // []) | length) > 0)"
done

title "Code, tests et pipeline"
_m20_e24_tests="$(_m20p_fichier_main plateforme/k8s releases/argocd/rbac-tests.txt)"
_m20_e24_n="$(grep -cE '^[[:space:]]*(oui|non)[[:space:]]' <<<"$_m20_e24_tests" || true)"
_m20_e24_non="$(grep -cE '^[[:space:]]*non[[:space:]]' <<<"$_m20_e24_tests" || true)"
check_output "rbac-tests.txt sur main : au moins 20 cas dont 10 refus (trouvés : ${_m20_e24_n:-0} cas, ${_m20_e24_non:-0} refus)" '^ok$' \
  bash -c '(( ${1:-0} >= 20 && ${2:-0} >= 10 )) && echo ok' _ "$_m20_e24_n" "$_m20_e24_non"
check_cmd "releases/argocd/policy.csv sur main" \
  _m20p_fichier_contient plateforme/k8s releases/argocd/policy.csv 'role:mediagenda-equipe'
check_cmd "outils/argocd-rbac-tests.sh sur main (rbac can, --policy-file)" \
  _m20p_fichier_contient plateforme/k8s outils/argocd-rbac-tests.sh 'rbac can' 'policy-file'
_m20_e24_pipe="$(_m20p_dernier_pipeline plateforme/k8s)"
_m20_e24_pid="$(jq -r '.id // empty' <<<"$_m20_e24_pipe" 2>/dev/null || true)"
if [[ -n "$_m20_e24_pid" ]]; then
  check_cmd "dernier pipeline de main de plateforme/k8s : un job de tests RBAC réussi" _m20p_jq \
    "$(_m20p_jobs plateforme/k8s "$_m20_e24_pid")" 'any(.[]; (.name | test("rbac"; "i")) and .status == "success")'
else
  check_cmd "dernier pipeline de main de plateforme/k8s (introuvable)" false
fi
check_cmd "docs/livraison/gitops/rbac.md sur main (policy.default, deny, matrice)" \
  _m20p_doc docs/livraison/gitops/rbac.md 'policy\.default' 'deny' 'role:mediagenda-equipe'
