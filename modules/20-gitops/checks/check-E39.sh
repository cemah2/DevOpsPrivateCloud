# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M20-E39 « Panne : la dérive revient sans cesse » : plus aucun second écrivain sur
# MédiAgenda dev et sur labo (gestionnaires de champs, ressources partagées entre Applications,
# HPA sans différence ignorée), puis une observation de 60 s (WB_M20_OBSERVATION) sans
# synchronisation automatique ni nouvelle génération du Deployment. RB-200, journal, panne close.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E39 — La dérive ne revient plus"
require_cmd jq kubectl curl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "$_m20x_app_dev : Synced, Healthy" _m20x_app_saine "$_m20x_app_dev"
  if _m20x_app_existe "$_m20x_app_labo"; then
    check_cmd "$_m20x_app_labo : Synced, Healthy" _m20x_app_saine "$_m20x_app_labo"
  fi
  check_cmd "aucune Application ne signale de ressource partagée (SharedResourceWarning)" _m20x_apps_sans 'SharedResourceWarning'
  _m20_e39_etrangers="$(_m20x_gestionnaires_etrangers "$_m20x_ns_dev" deploy mediagenda)"
  check_cmd "mediagenda-dev : Deployment mediagenda écrit par Argo CD seul (autres : ${_m20_e39_etrangers:-aucun})" \
    test -z "$_m20_e39_etrangers"
  # Un HPA en dev n'est admis que si la différence de réplicas est ignorée par l'Application (et respectée à la synchro).
  _m20_e39_hpa_coherent() {
    kube -n "$_m20x_ns_dev" get hpa -o json 2>/dev/null | jq -e '.items | length == 0' >/dev/null 2>&1 && return 0
    _m20x_app_jq "$_m20x_app_dev" '([.spec.ignoreDifferences[]? | select(.kind == "Deployment")
        | select(((.jsonPointers // []) | index("/spec/replicas")) or ((.jqPathExpressions // []) | any(test("replicas")))
                 or ((.managedFieldsManagers // []) | index("kube-controller-manager")))] | length > 0)
      and ((.spec.syncPolicy.syncOptions // []) | index("RespectIgnoreDifferences=true"))'
  }
  check_cmd "mediagenda-dev : pas de HPA, ou réplicas ignorés et respectés par l'Application" _m20_e39_hpa_coherent
  _m20_e39_liaisons_etrangeres() {
    kube -n "$_m20x_ns_dev" get rolebindings -o json 2>/dev/null | jq -e --arg ns "$_m20x_ns_dev" '
      [.items[] | select(any(.subjects[]?; .kind == "ServiceAccount" and (.namespace // $ns) != $ns
        and ((.namespace // "") | test("^(argocd|kube-system|gitlab-agent|cnpg-system)$") | not)))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "mediagenda-dev : aucun droit accordé à un compte de service d'un espace hors plateforme" _m20_e39_liaisons_etrangeres
  # Observation : plus aucune bataille pendant WB_M20_OBSERVATION secondes.
  _m20_e39_calme() {
    local d="${WB_M20_OBSERVATION:-60}" a avant apres gen1 gen2
    avant=""
    for a in "$_m20x_app_dev" "$_m20x_app_labo"; do
      avant+="$(_m20x_app "$a" | jq -r '[.status.operationState.startedAt // "", (.status.history // [] | length)] | join(" ")' 2>/dev/null);"
    done
    gen1="$(kube -n "$_m20x_ns_dev" get deploy mediagenda -o jsonpath='{.metadata.generation}' 2>/dev/null)"
    sleep "$d"
    apres=""
    for a in "$_m20x_app_dev" "$_m20x_app_labo"; do
      apres+="$(_m20x_app "$a" | jq -r '[.status.operationState.startedAt // "", (.status.history // [] | length)] | join(" ")' 2>/dev/null);"
    done
    gen2="$(kube -n "$_m20x_ns_dev" get deploy mediagenda -o jsonpath='{.metadata.generation}' 2>/dev/null)"
    [[ "$avant" == "$apres" && -n "$gen1" && "$gen1" == "$gen2" ]]
  }
  echo "  …observation de ${WB_M20_OBSERVATION:-60} s (aucune synchronisation ni nouvelle génération attendue)"
  check_cmd "aucune synchronisation automatique ni changement du Deployment pendant l'observation" _m20_e39_calme
fi
check_cmd "plateforme/outils : outil qui-ecrit.sh présent" _m20x_fichier_present plateforme/outils qui-ecrit.sh
if _m20x_argo_lisible; then
  check_cmd "$_m20x_app_dev : une ressource partagée fait échouer la synchronisation (FailOnSharedResource=true)" \
    _m20x_app_jq "$_m20x_app_dev" '(.spec.syncPolicy.syncOptions // []) | index("FailOnSharedResource=true")'
fi
check_cmd "RB-200 : section sur la dérive qui revient" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(dérive|drift|selfHeal)'
check_cmd "journal de diagnostic de INC-4739 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4739'
check_cmd "panne M20-E39 close (lab/bin/break 20 39 --annuler après réparation)" _m20x_aucune_panne_active E39
