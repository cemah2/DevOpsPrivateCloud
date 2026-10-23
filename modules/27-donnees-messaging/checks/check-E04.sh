# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E04.sh — M27-E04 : topologie déclarative et MédiNotif en recette
# À lancer depuis adm01. Lecture seule : objets du Topology Operator (espace messagerie), API de
# gestion de RabbitMQ par wb-checks (métadonnées : files, politiques, liaisons, consommateurs,
# connexions ; jamais les messages), Applications Argo CD, espace medinotif-recette, Prometheus.

# shellcheck source=_m27-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-decouverte.sh"

title "M27-E04 — Topologie déclarative et MédiNotif en recette"
require_cmd jq kubectl curl awk

_m27d_e04_env="$_M27D_ENV_RECETTE"
_m27d_e04_vh="medinotif-${_m27d_e04_env}"
_m27d_e04_ns="medinotif-${_m27d_e04_env}"

# --- 1. Topologie déclarée ------------------------------------------------------------------------------
_m27d_e04_app="$(_m27d_app rabbitmq-topologie)"
check_cmd "Application rabbitmq-topologie : plateforme/donnees, chemin topologie" _m27d_app_source "$_m27d_e04_app" "plateforme/donnees" "topologie"
check_cmd "Application rabbitmq-topologie : synchronisée et saine" _m27d_json "$_m27d_e04_app" "$_M27D_APP_SAINE"
_m27d_e04_perm="$(_m27d_k get permissions.rabbitmq.com -n messagerie -o json)"
check_cmd "Permission de medinotif-${_m27d_e04_env} : lire notifications, rien d'autre" _m27d_json "$_m27d_e04_perm" \
  'any(.items[]; .spec.vhost == $v and ((.spec.user // .spec.userReference.name) == $u)
     and .spec.permissions.read == "^notifications$" and .spec.permissions.write == "^$" and .spec.permissions.configure == "^$")' \
  --arg v "$_m27d_e04_vh" --arg u "medinotif-${_m27d_e04_env}"
check_cmd "Permission de mediagenda-${_m27d_e04_env} : écrire sur l'échange notifications, rien d'autre" _m27d_json "$_m27d_e04_perm" \
  'any(.items[]; .spec.vhost == $v and ((.spec.user // .spec.userReference.name) == $u)
     and .spec.permissions.write == "^notifications$" and .spec.permissions.read == "^$" and .spec.permissions.configure == "^$")' \
  --arg v "$_m27d_e04_vh" --arg u "mediagenda-${_m27d_e04_env}"
check_cmd "utilisateurs medinotif-${_m27d_e04_env} et mediagenda-${_m27d_e04_env} : mot de passe par un Secret importé, sans étiquette d'administration" _m27d_json \
  "$(_m27d_k get users.rabbitmq.com -n messagerie -o json)" \
  '[.items[] | select(.metadata.name == ("medinotif-" + $e) or .metadata.name == ("mediagenda-" + $e))
     | select((.spec.importCredentialsSecret.name // "") != "" and ((.spec.tags // []) | length) == 0)] | length == 2' \
  --arg e "$_m27d_e04_env"
check_cmd "identifiants des utilisateurs lus dans OpenBao (ExternalSecret prêts, ClusterSecretStore openbao)" _m27d_json \
  "$(_m27d_k get externalsecrets.external-secrets.io -n messagerie -o json)" \
  '[.items[] | select(any((.spec.dataFrom // [])[]; (.extract.key // "") as $k | $k == ("medinotif/" + $e + "/amqp") or $k == ("mediagenda/" + $e + "/amqp")))
     | select(.spec.secretStoreRef.kind == "ClusterSecretStore" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 2' \
  --arg e "$_m27d_e04_env"

# --- 2. Ce que RabbitMQ en a fait (API de gestion) --------------------------------------------------------
if ! _m27d_rmq_lisible; then
  _ko "API de gestion injoignable avec le compte des checks : contrôles de RabbitMQ impossibles"
else
  _m27d_e04_q="$(_m27d_rmq "queues/${_m27d_e04_vh}")"
  check_cmd "vhost ${_m27d_e04_vh} visible du compte des checks (permission vide accordée)" bash -c '[[ -n "$1" && "$1" != *not_found* ]]' _ "$_m27d_e04_q"
  check_cmd "file notifications : quorum, politique de rebut effective (échange notifications.rebut, limite de livraison)" _m27d_json "$_m27d_e04_q" \
    'any(.[]; .name == "notifications" and .type == "quorum"
       and .effective_policy_definition["dead-letter-exchange"] == "notifications.rebut"
       and ((.effective_policy_definition["delivery-limit"] // 0) > 0))'
  check_cmd "file notifications.rebut : quorum" _m27d_json "$_m27d_e04_q" 'any(.[]; .name == "notifications.rebut" and .type == "quorum")'
  check_cmd "file notifications répliquée sur les 3 nœuds" _m27d_json "$_m27d_e04_q" \
    'any(.[]; .name == "notifications" and ((.members // []) | length) == 3)'
  check_cmd "échange notifications de type direct, lié à la file notifications (clé notifications)" _m27d_json \
    "$(_m27d_rmq "bindings/${_m27d_e04_vh}")" \
    'any(.[]; .source == "notifications" and .destination == "notifications" and .destination_type == "queue" and .routing_key == "notifications")'
  check_cmd "MédiNotif consomme la file notifications (au moins un consommateur, acquittements manuels)" _m27d_json \
    "$(_m27d_rmq "consumers/${_m27d_e04_vh}")" \
    'any(.[]; .queue.name == "notifications" and .ack_required == true and .channel_details.user == $u)' --arg u "medinotif-${_m27d_e04_env}"
  check_cmd "connexion de medinotif-${_m27d_e04_env} chiffrée (AMQPS)" _m27d_json "$(_m27d_rmq connections)" \
    'any(.[]; .user == $u and .vhost == $v and .ssl == true)' --arg u "medinotif-${_m27d_e04_env}" --arg v "$_m27d_e04_vh"
  check_cmd "au moins un message au rebut (notifications.rebut)" _m27d_json "$_m27d_e04_q" \
    'any(.[]; .name == "notifications.rebut" and (.messages // 0) >= 1)'
fi

# --- 3. MédiNotif par GitOps ------------------------------------------------------------------------------
check_cmd "ApplicationSet medinotif (dépôt medinotif/deploiement)" _m27d_json \
  "$(_m27d_k get applicationsets.argoproj.io medinotif -n argocd -o json)" \
  '(.spec.template.spec.source.repoURL // "") | test("medinotif/deploiement")'
_m27d_e04_appm="$(_m27d_app "medinotif-${_m27d_e04_env}")"
check_cmd "Application medinotif-${_m27d_e04_env} : projet medinotif, synchronisée et saine" _m27d_json "$_m27d_e04_appm" \
  ".spec.project == \"medinotif\" and $_M27D_APP_SAINE"
check_cmd "espace ${_m27d_e04_ns} : Pod Security « restricted », étiquette d'équipe" _m27d_json \
  "$(_m27d_k get namespace "$_m27d_e04_ns" -o json)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted" and (.metadata.labels["medisphere.internal/equipe"] // "") != ""'
_m27d_e04_dep="$(_m27d_k get deployment medinotif -n "$_m27d_e04_ns" -o json)"
check_cmd "Deployment medinotif prêt, image medinotif-worker PAR EMPREINTE" _m27d_json "$_m27d_e04_dep" \
  '(.status.readyReplicas // 0) >= 1 and any(.spec.template.spec.containers[];
     .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/medinotif-worker(:[^@]+)?@sha256:[0-9a-f]{64}$"))'
check_cmd "MédiNotif ne déclare pas la file (MEDINOTIF_DECLARER_FILE=0)" _m27d_json "$_m27d_e04_dep" \
  'any(.spec.template.spec.containers[].env[]?; .name == "MEDINOTIF_DECLARER_FILE" and .value == "0")'
check_cmd "URL AMQP lue dans le Secret medinotif-amqp (jamais en clair)" _m27d_json "$_m27d_e04_dep" \
  'any(.spec.template.spec.containers[].env[]?; .name == "MEDINOTIF_AMQP_URL" and .valueFrom.secretKeyRef.name == "medinotif-amqp")'
check_cmd "ExternalSecret medinotif-amqp prêt (SecretStore openbao de l'espace)" _m27d_json \
  "$(_m27d_k get externalsecrets.external-secrets.io medinotif-amqp -n "$_m27d_e04_ns" -o json)" \
  '.spec.secretStoreRef.name == "openbao" and (.spec.secretStoreRef.kind // "SecretStore") == "SecretStore"
   and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
_m27d_e04_env_m="$(_m27d_prom "sum(medinotif_messages_total{namespace=\"${_m27d_e04_ns}\",resultat=\"envoye\"})")"
check_cmd "notifications envoyées par MédiNotif en recette (medinotif_messages_total{resultat=\"envoye\"} = ${_m27d_e04_env_m})" \
  _m27d_positif "$_m27d_e04_env_m"
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/messagerie-topologie.md" \
  _m27d_doc_contient "${_M27D_DOC}/messagerie-topologie.md" 'notifications\.rebut'
