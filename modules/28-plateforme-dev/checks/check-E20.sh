# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E20.sh — M28-E20 « Des pods redémarrent en boucle depuis l'autoscaling » : VPA de recette en Off,
# aucun VPA actif hors wb-essais, Argo CD ne possède pas spec.replicas des charges autoscalées de
# recette, ni éviction du VPA ni OOMKilled ni oscillation récents ; RB-286 ; panne close. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E20 — Plus d'oscillation sous l'autoscaling"
require_cmd kubectl jq

# _m28_e20_replicas_hors_argocd ESPACE TYPE NOM — argocd-controller ne possède pas spec.replicas.
_m28_e20_replicas_hors_argocd() {
  kube -n "$1" get "$2" "$3" --show-managed-fields -o json 2>/dev/null | jq -e '
    [.metadata.managedFields[]? | select(.manager | test("argocd")) | .fieldsV1["f:spec"]["f:replicas"]? // empty] | length == 0' >/dev/null 2>&1
}
_m28_e20_oscillation() {
  local n
  n="$(_m28x_evenements medinotif-recette ScalingReplicaSet 10)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] && ((n < 6))
}

if _m28p_api_repond; then
  check_cmd "aucun VPA actif (updateMode autre que Off) hors wb-essais" _m28p_kq \
    '[.items[] | select(.metadata.namespace != "wb-essais" and (.spec.updatePolicy.updateMode // "Auto") != "Off")] | length == 0' \
    verticalpodautoscalers.autoscaling.k8s.io -A
  check_cmd "Rollout mediagenda de recette : spec.replicas non géré par Argo CD" _m28_e20_replicas_hors_argocd mediagenda-recette rollouts.argoproj.io mediagenda
  check_cmd "Deployment medinotif de recette : spec.replicas non géré par Argo CD" _m28_e20_replicas_hors_argocd medinotif-recette deployments medinotif
  check_cmd "mediagenda-recette : aucune éviction du VPA depuis 15 min" _m28x_aucun_evenement mediagenda-recette EvictedByVPA 15
  check_cmd "mediagenda-recette : aucun conteneur OOMKilled depuis 15 min" _m28x_aucun_oom mediagenda-recette app.kubernetes.io/name=mediagenda 15
  check_cmd "medinotif-recette : pas d'oscillation de l'effectif (moins de 6 changements en 10 min)" _m28_e20_oscillation
else
  skip "VPA, Rollout, événements" "l'API ne répond pas au compte des checks"
fi
check_cmd "RB-286 publié (main) : qui écrit, VPA, replicas" _m28p_doc RB-286 'managedFields|managed-fields' 'VPA' 'replicas'
check_cmd "panne M28-E20 close (lab/bin/break 28 20 --annuler après réparation)" _m28x_aucune_panne_active E20
