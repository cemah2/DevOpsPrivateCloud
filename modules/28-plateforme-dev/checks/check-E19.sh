# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E19.sh — M28-E19 « MédiNotif ne monte plus en charge » : ScaledObject de recette prêt, sans
# pause, sur le bon vhost, sans erreur de scaler ; file sans retard ; aucune politique qui coupe keda de
# messagerie ; RB-285 ; panne close. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E19 — MédiNotif suit de nouveau sa file"
require_cmd kubectl jq curl

_m28_e19_pas_de_coupure() {
  kube get ciliumnetworkpolicies -A -o json 2>/dev/null | jq -e '
    [.items[] | select(.metadata.namespace == "keda" or .metadata.namespace == "messagerie")
              | select(((.spec.egressDeny // []) + (.spec.ingressDeny // [])) | length > 0)] | length == 0' >/dev/null 2>&1
}
if _m28p_api_repond; then
  check_cmd "ScaledObject medinotif de recette : Ready et sans pause" _m28p_so_ok medinotif-recette "$_M28P_SO_PRET"
  check_cmd "déclencheur rabbitmq de recette sur le vhost medinotif-recette et la file notifications" _m28p_so_ok medinotif-recette \
    '[.spec.triggers[] | select(.type == "rabbitmq") | .metadata] | length >= 1
     and all(.[]; .vhostName == "medinotif-recette" and .queueName == "notifications")'
  check_cmd "aucune politique de refus ajoutée entre keda et messagerie" _m28_e19_pas_de_coupure
else
  skip "ScaledObject et politiques" "l'API ne répond pas au compte des checks"
fi
_m28_e19_sans_erreur() {
  ! _m28p_prom_vrai 'sum(increase(keda_scaler_detail_errors_total{exported_namespace="medinotif-recette"}[10m]))'
}
if _m28p_prom_repond; then
  check_cmd "aucune erreur du scaler de recette ces 10 dernières minutes" _m28_e19_sans_erreur
else
  skip "erreurs du scaler" "Prometheus ne répond pas"
fi
_m28_e19_file() { rabbitmq_api "queues/medinotif-recette/notifications" 2>/dev/null | jq -e '(.messages_ready // 0) < 500' >/dev/null 2>&1; }
check_cmd "file notifications de recette sans retard (moins de 500 messages prêts)" _m28_e19_file
check_cmd "RB-285 publié (main) : arbre de décision de l'autoscaling" _m28p_doc RB-285 'pause|paused' '401' '404' 'external.metrics'
check_cmd "panne M28-E19 close (lab/bin/break 28 19 --annuler après réparation)" _m28x_aucune_panne_active E19
