# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M27-E10 : MédiNotif sur Kafka, comparaison, puis RETRAIT complet
# À lancer depuis adm01 APRÈS le retrait : avant, il signale ce qui reste. Lecture seule :
# Applications Argo CD, espaces, types d'API servis (découverte), volumes persistants si le compte
# des checks peut les lister, documentation sur main.

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E10 — MédiNotif sur Kafka : comparaison, puis retrait"
require_cmd jq kubectl curl

# --- 1. La comparaison ---------------------------------------------------------------------------------------
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/comparatif-messagerie.md (RabbitMQ et Kafka)" bash -c '
  grep -qi "rabbitmq" <<<"$1" && grep -qi "kafka" <<<"$1"' _ "$(_m27d_contenu_main "$_M27D_P_DOC" "${_M27D_DOC}/comparatif-messagerie.md")"
check_cmd "comparatif : des mesures chiffrées (s, ms ou messages par seconde)" \
  _m27d_doc_contient "${_M27D_DOC}/comparatif-messagerie.md" '[0-9]+([,.][0-9]+)? ?(ms|s|msg/s|messages/s)([^a-z]|$)'
check_cmd "comparatif : plus aucune valeur à compléter (<MESURE>)" bash -c '
  [[ -n "$1" ]] && ! grep -q "<MESURE>" <<<"$1"' _ "$(_m27d_contenu_main "$_M27D_P_DOC" "${_M27D_DOC}/comparatif-messagerie.md")"
check_cmd "comparatif : les trois scénarios (worker tué, nœud perdu, consommateur lent)" bash -c '
  grep -Eqi "tu[ée]" <<<"$1" && grep -Eqi "n(œ|oe)ud" <<<"$1" && grep -Eqi "lent" <<<"$1"' _ \
  "$(_m27d_contenu_main "$_M27D_P_DOC" "${_M27D_DOC}/comparatif-messagerie.md")"

# --- 2. Le retrait ------------------------------------------------------------------------------------------
check_cmd "Application kafka-essai supprimée" _m27o_absent applications.argoproj.io kafka-essai -n argocd
check_cmd "espace kafka-essai supprimé" _m27o_absent namespace kafka-essai
check_cmd "plus aucune CRD de Strimzi (kafka.strimzi.io)" _m27o_groupe_absent kafka.strimzi.io
check_cmd "plus aucune CRD de Strimzi (core.strimzi.io)" _m27o_groupe_absent core.strimzi.io
if [[ "$(kube auth can-i list persistentvolumes 2>/dev/null || true)" == yes ]]; then
  check_cmd "aucun volume persistant de l'essai (réclamé par kafka-essai)" _m27d_json \
    "$(_m27d_k get pv -o json)" '[.items[] | select((.spec.claimRef.namespace // "") == "kafka-essai")] | length == 0'
else
  skip "volumes persistants de l'essai" "le compte des checks ne liste pas les PV : vérifie à la main (kubectl get pv | grep kafka-essai)"
fi
check_cmd "plus aucune ClusterRole de Strimzi" _m27d_json "$(_m27d_k get clusterroles -o json)" \
  '[.items[] | select(.metadata.name | test("strimzi"))] | length == 0'
check_cmd "kafka-essai.md : retrait effectif daté" \
  _m27d_doc_contient "${_M27D_DOC}/kafka-essai.md" 'retrait effectif[^0-9]*[0-9]{4}-[0-9]{2}-[0-9]{2}'
