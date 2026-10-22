# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M20-E35 « Panne : l'application reste OutOfSync » : MédiAgenda dev Synced et
# Healthy sans élagage en attente, aucune Application de l'ApplicationSet mediagenda en erreur de
# comparaison, version de Kustomize épinglée seulement si elle est déclarée, bases CNPG protégées
# de l'élagage, RB-200 et journal à jour, panne close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E35 — MédiAgenda dev reste Synced"
require_cmd jq kubectl curl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "$_m20x_app_dev : Synced, Healthy, dernière opération réussie, aucune erreur" _m20x_app_saine "$_m20x_app_dev"
  check_cmd "$_m20x_app_dev : aucune ressource en attente d'élagage (requiresPruning)" \
    _m20x_app_jq "$_m20x_app_dev" '[.status.resources[]? | select(.requiresPruning // false)] | length == 0'
  check_cmd "$_m20x_app_dev : aucune opération bloquée (pas d'opération en cours depuis plus de 10 min)" \
    _m20x_app_jq "$_m20x_app_dev" '((.status.operationState.phase // "") != "Running")
      or ((now - ((.status.operationState.startedAt // "1970-01-01T00:00:00Z") | fromdateiso8601)) < 600)'
  check_cmd "mediagenda-dev : aucun PersistentVolumeClaim en attente (Pending)" \
    _m20x_kq '[.items[] | select(.status.phase == "Pending")] | length == 0' -n "$_m20x_ns_dev" pvc
  check_cmd "$_m20x_app_dev : aucune ressource OutOfSync" \
    _m20x_app_jq "$_m20x_app_dev" '[.status.resources[]? | select(.status == "OutOfSync")] | length == 0'
  _m20_e35_apps="$(_m20x_apps_de_appset mediagenda)"
  if [[ -z "$_m20_e35_apps" ]]; then
    check_cmd "ApplicationSet mediagenda : au moins une Application générée (M20-E10)" false
  else
    for _m20_e35_a in $_m20_e35_apps; do
      check_cmd "$_m20_e35_a : aucune erreur de comparaison ni de spécification" \
        _m20x_app_jq "$_m20_e35_a" '[.status.conditions[]? | select(.type | test("ComparisonError|InvalidSpecError"))] | length == 0'
    done
  fi
  # Une version de Kustomize épinglée doit être déclarée (kustomize.path.<version>) dans argocd-cm.
  _m20_e35_versions_declarees() {
    local cm v
    cm="$(_m20x_cm "$_m20x_ns" argocd-cm)" || return 1
    for v in $(kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null |
      jq -r '[.items[] | (.spec.source.kustomize.version // empty), (.spec.sources[]?.kustomize.version // empty)] | unique[]'); do
      jq -e --arg k "kustomize.path.$v" '.data[$k] != null' >/dev/null 2>&1 <<<"$cm" || return 1
    done
  }
  check_cmd "versions de Kustomize épinglées par les Applications toutes déclarées dans argocd-cm" _m20_e35_versions_declarees
  check_cmd "bases CNPG de mediagenda-dev présentes" _m20x_kq '.items | length > 0' -n "$_m20x_ns_dev" clusters.postgresql.cnpg.io
  check_cmd "bases CNPG de mediagenda-* protégées de l'élagage (Prune=false)" \
    _m20x_cnpg_proteges "$_m20x_ns_dev" "$_m20x_ns_recette" "$_m20x_ns_prod"
fi
check_cmd "plateforme/outils : outil argocd-diagnostic.sh présent" _m20x_fichier_present plateforme/outils argocd-diagnostic.sh
check_cmd "RB-200 : section sur l'application qui reste OutOfSync" _m20x_doc_contient "$_m20x_rb200" '^#+ .*OutOfSync'
check_cmd "journal de diagnostic de INC-4735 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4735'
check_cmd "aucune MR de panne restée ouverte dans mediagenda/deploiement et plateforme/gitops" \
  bash -c '(( $1 + $2 == 0 ))' _ "$(_m20x_mr_lucas_ouvertes mediagenda/deploiement)" "$(_m20x_mr_lucas_ouvertes plateforme/gitops)"
check_cmd "panne M20-E35 close (lab/bin/break 20 35 --annuler après réparation)" _m20x_aucune_panne_active E35
