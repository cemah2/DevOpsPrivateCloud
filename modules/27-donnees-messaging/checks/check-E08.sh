# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M27-E08 : MédiAgenda publie les notifications, MédiNotif en production
# À lancer depuis adm01. Lecture seule : objets de mediagenda-<env>, medinotif-prod et messagerie,
# Applications Argo CD, API de gestion de RabbitMQ (wb-checks : métadonnées), Prometheus,
# documentation sur main, et ton dossier local ~/m27/e08/.

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E08 — MédiAgenda publie, MédiNotif en production"
require_cmd jq kubectl curl awk

_m27o_e08_cnp="$(_m27d_k get ciliumnetworkpolicies.cilium.io -n messagerie -o json)"

# --- 1. L'éditeur, en recette et en prod --------------------------------------------------------------------
for _m27o_e08_env in "$_M27D_ENV_RECETTE" "$_M27D_ENV_PROD"; do
  _m27o_e08_ns="mediagenda-${_m27o_e08_env}"
  check_cmd "$_m27o_e08_env : l'API lit MEDIAGENDA_AMQP_URL dans un Secret" _m27d_json \
    "$(_m27d_k get deployment mediagenda -n "$_m27o_e08_ns" -o json)" \
    'any(.spec.template.spec.containers[].env[]?; .name == "MEDIAGENDA_AMQP_URL" and (.valueFrom.secretKeyRef.name // "") != "")'
  check_cmd "$_m27o_e08_env : pods de l'API prêts" bash -c '[[ "$1" -ge 1 ]]' _ \
    "$(_m27d_pods_prets "$_m27o_e08_ns" app.kubernetes.io/name=mediagenda)"
  check_cmd "$_m27o_e08_env : une NetworkPolicy ouvre AMQPS (5671) de l'API vers messagerie" _m27d_json \
    "$(_m27d_k get networkpolicies -n "$_m27o_e08_ns" -o json)" \
    'any(.items[]; (.spec.podSelector.matchLabels["app.kubernetes.io/name"] // "") == "mediagenda"
       and any(.spec.egress[]?; any(.to[]?; (.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // "") == "messagerie")
                               and any(.ports[]?; .port == 5671 or .port == "5671")))'
  check_cmd "$_m27o_e08_env : la grappe accepte AMQPS depuis $_m27o_e08_ns (CNP de messagerie)" _m27d_json "$_m27o_e08_cnp" \
    'any(.items[].spec.ingress[]?; any(.fromEndpoints[]?; .matchLabels["io.kubernetes.pod.namespace"] == $n)
       and any(.toPorts[]?.ports[]?; .port == "5671" or .port == 5671))' --arg n "$_m27o_e08_ns"
  _m27o_e08_pub="$(_m27d_prom "sum(increase(mediagenda_notifications_total{namespace=\"${_m27o_e08_ns}\",resultat=\"publiee\"}[7d]))")"
  check_cmd "$_m27o_e08_env : publications réussies (mediagenda_notifications_total{resultat=\"publiee\"}, 7 j : ${_m27o_e08_pub})" \
    _m27d_positif "$_m27o_e08_pub"
done

# --- 2. La topologie de prod ----------------------------------------------------------------------------------
_m27o_e08_vh="medinotif-${_M27D_ENV_PROD}"
_m27o_e08_perm="$(_m27d_k get permissions.rabbitmq.com -n messagerie -o json)"
check_cmd "Permission de medinotif-${_M27D_ENV_PROD} : lire notifications, rien d'autre" _m27d_json "$_m27o_e08_perm" \
  'any(.items[]; .spec.vhost == $v and ((.spec.user // .spec.userReference.name) == $u)
     and .spec.permissions.read == "^notifications$" and .spec.permissions.write == "^$" and .spec.permissions.configure == "^$")' \
  --arg v "$_m27o_e08_vh" --arg u "medinotif-${_M27D_ENV_PROD}"
check_cmd "Permission de mediagenda-${_M27D_ENV_PROD} : écrire sur l'échange notifications, rien d'autre" _m27d_json "$_m27o_e08_perm" \
  'any(.items[]; .spec.vhost == $v and ((.spec.user // .spec.userReference.name) == $u)
     and .spec.permissions.write == "^notifications$" and .spec.permissions.read == "^$" and .spec.permissions.configure == "^$")' \
  --arg v "$_m27o_e08_vh" --arg u "mediagenda-${_M27D_ENV_PROD}"
if ! _m27d_rmq_lisible; then
  _ko "API de gestion injoignable avec le compte des checks : topologie de prod non vérifiable"
else
  _m27o_e08_q="$(_m27d_rmq "queues/${_m27o_e08_vh}")"
  check_cmd "vhost ${_m27o_e08_vh} : file notifications quorum, 3 membres, rebut effectif" _m27d_json "$_m27o_e08_q" \
    'any(.[]; .name == "notifications" and .type == "quorum" and ((.members // []) | length) == 3
       and .effective_policy_definition["dead-letter-exchange"] == "notifications.rebut")'
  check_cmd "vhost ${_m27o_e08_vh} : file notifications.rebut quorum" _m27d_json "$_m27o_e08_q" \
    'any(.[]; .name == "notifications.rebut" and .type == "quorum")'
  check_cmd "vhost ${_m27o_e08_vh} : au moins deux consommateurs de notifications (medinotif-${_M27D_ENV_PROD})" _m27d_json \
    "$(_m27d_rmq "consumers/${_m27o_e08_vh}")" \
    '[.[] | select(.queue.name == "notifications" and .channel_details.user == $u)] | length >= 2' --arg u "medinotif-${_M27D_ENV_PROD}"
fi

# --- 3. MédiNotif en production -------------------------------------------------------------------------------
_m27o_e08_nsn="medinotif-${_M27D_ENV_PROD}"
check_cmd "Application medinotif-${_M27D_ENV_PROD} : projet medinotif, synchronisée et saine" _m27d_json \
  "$(_m27d_app "medinotif-${_M27D_ENV_PROD}")" ".spec.project == \"medinotif\" and $_M27D_APP_SAINE"
check_cmd "Application medinotif-${_M27D_ENV_PROD} : synchronisation MANUELLE (pas d'automated)" _m27d_json \
  "$(_m27d_app "medinotif-${_M27D_ENV_PROD}")" '(.spec.syncPolicy.automated // null) == null'
_m27o_e08_dep="$(_m27d_k get deployment medinotif -n "$_m27o_e08_nsn" -o json)"
check_cmd "Deployment medinotif (prod) : au moins 2 réplicas prêts, image signée PAR EMPREINTE" _m27d_json "$_m27o_e08_dep" \
  '(.status.readyReplicas // 0) >= 2 and all(.spec.template.spec.containers[];
     .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/medinotif-worker(:[^@]+)?@sha256:[0-9a-f]{64}$"))'
check_cmd "MédiNotif (prod) : pods sur au moins 2 nœuds différents" bash -c '[[ "$1" -ge 2 ]]' _ \
  "$(_m27d_noeuds_distincts "$_m27o_e08_nsn" app.kubernetes.io/name=medinotif)"
check_cmd "MédiNotif (prod) : PodDisruptionBudget" _m27d_json "$(_m27d_k get pdb -n "$_m27o_e08_nsn" -o json)" \
  'any(.items[]; .spec.selector.matchLabels["app.kubernetes.io/name"] == "medinotif")'
_m27o_e08_env_m="$(_m27d_prom "sum(increase(medinotif_messages_total{namespace=\"${_m27o_e08_nsn}\",resultat=\"envoye\"}[7d]))")"
check_cmd "MédiNotif a envoyé en prod (medinotif_messages_total{resultat=\"envoye\"}, 7 j : ${_m27o_e08_env_m})" \
  _m27d_positif "$_m27o_e08_env_m"

# --- 4. Documentation et dossier ------------------------------------------------------------------------------
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/messagerie-topologie.md décrit la prod" \
  _m27d_doc_contient "${_M27D_DOC}/messagerie-topologie.md" "medinotif-${_M27D_ENV_PROD}"
check_cmd "messagerie-topologie.md : l'éditeur (MEDIAGENDA_AMQP_URL) est documenté" \
  _m27d_doc_contient "${_M27D_DOC}/messagerie-topologie.md" 'MEDIAGENDA_AMQP_URL'
check_cmd "dossier ${_M27O_TRAVAIL}/e08 présent et non vide" bash -c \
  '[[ -d "$1" ]] && [[ -n "$(find "$1" -type f -size +0 -print -quit 2>/dev/null)" ]]' _ "${_M27O_TRAVAIL}/e08"
