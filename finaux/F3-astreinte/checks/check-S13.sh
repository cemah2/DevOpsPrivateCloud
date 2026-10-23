# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# check-S13.sh — F3-S13 « Vendredi : les notifications s'accumulent » (INC-5913) : la file
# notifications de medinotif-prod est consommée (au moins deux consommateurs, en baisse ou sous le
# seuil), sa politique effective est celle de la topologie (rebut et limite de livraison) ; le
# ScaledObject de MédiNotif (prod) est prêt, hors repli, avec le maximum du dépôt ; MédiNotif est
# disponible ; trace de l'incident.
# Lecture seule : rabbitmq_api (compte wb-checks, étiquette monitoring), kube, GitLab (fichier du dépôt).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S13 — Les notifications repartent (INC-5913)"
require_cmd jq kubectl curl yq

_f3s_sante

# --- File ------------------------------------------------------------------------------------------------
_s13_q="$(rabbitmq_api queues/medinotif-prod/notifications 2>/dev/null || true)"
check_cmd "file notifications (prod) : au moins deux consommateurs" _f3f_json "$_s13_q" '(.consumers // 0) >= 2'
check_cmd "file notifications (prod) : politique effective = celle de la topologie (rebut, limite de livraison positive)" \
  _f3f_json "$_s13_q" '(.policy // "") == "notifications-rebut"
    and (.effective_policy_definition["dead-letter-exchange"] // "") == "notifications.rebut"
    and ((.effective_policy_definition["delivery-limit"] // 20) > 0)'
_s13_seuil="${WB_F3_S13_SEUIL:-2000}"
check_cmd "file notifications (prod) : moins de $_s13_seuil messages en attente, ou consommée plus vite qu'alimentée" \
  _f3f_json "$_s13_q" '((.messages // 0) < ($s | tonumber))
    or ((.message_stats.ack_details.rate // 0) >= (.message_stats.publish_details.rate // 0) and (.message_stats.ack_details.rate // 0) > 0)' \
  --arg s "$_s13_seuil"
_s13_r="$(rabbitmq_api queues/medinotif-prod/notifications.rebut 2>/dev/null || true)"
check_cmd "file de rebut notifications.rebut (prod) présente (quorum)" _f3f_json "$_s13_r" '.type == "quorum"'

# --- KEDA ------------------------------------------------------------------------------------------------
_s13_so="$(_f3f_k -n medinotif-prod get scaledobjects.keda.sh medinotif -o json)"
check_cmd "ScaledObject medinotif (prod) Ready" _f3f_condition "$_s13_so" Ready
check_cmd "ScaledObject medinotif (prod) hors repli (condition Fallback non vraie : le scaler RabbitMQ répond)" \
  _f3f_json "$_s13_so" '[.status.conditions[]? | select(.type == "Fallback" and .status == "True")] | length == 0'
_s13_git_max="$(_f3f_gl_fichier "$_f3f_notif" overlays/prod/keda/scaledobject.yaml | yq -r 'select(.kind == "ScaledObject") | .spec.maxReplicaCount // ""' 2>/dev/null | head -n 1 || true)"
check_cmd "ScaledObject medinotif (prod) : maxReplicaCount = valeur du dépôt ($_f3f_notif : ${_s13_git_max:-?})" \
  _f3f_json "$_s13_so" '(.spec.maxReplicaCount | tostring) == $m and ($m | tonumber) > (.spec.minReplicaCount // 0)' \
  --arg m "${_s13_git_max:-x}"

# --- MédiNotif -------------------------------------------------------------------------------------------
_s13_dep="$(_f3f_k -n medinotif-prod get deployment medinotif -o json)"
check_cmd "Deployment medinotif (prod) : au moins deux pods disponibles" \
  _f3f_json "$_s13_dep" '(.status.availableReplicas // 0) >= 2'
_s13_pods="$(_f3f_k -n medinotif-prod get pods -l app.kubernetes.io/name=medinotif -o json)"
check_cmd "pods MédiNotif (prod) : aucun en CrashLoopBackOff" \
  _f3f_json "$_s13_pods" '(.items | length) > 0 and all(.items[]; all(.status.containerStatuses[]?; (.state.waiting.reason // "") != "CrashLoopBackOff"))'

# --- Trace -----------------------------------------------------------------------------------------------
check_cmd "main courante : la non-perte des notifications est vérifiée et consignée (rebut, file, rejeu)" \
  _f3f_journal_cite INC-5913 'rebut|perte|perdu'
check_cmd "RB-338 publié (docs/exploitation/runbooks/)" _f3f_rb_present RB-338
_f3s_trace INC-5913 2
