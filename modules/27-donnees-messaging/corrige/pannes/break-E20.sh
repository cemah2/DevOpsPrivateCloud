# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions yq entre apostrophes
# break-E20.sh — M27-E20 « Panne : MédiNotif ne consomme plus » (vhost medinotif-recette seulement)
#
# Avant toute injection : export des définitions de la grappe et du vhost de recette (état local, 600).
#   1. Permission de l'utilisateur medinotif-recette « durcie » par Lucas dans la topologie
#      (plateforme/donnees, topologie/medinotif-recette) : lecture limitée à notifications.rebut. Les
#      connexions de medinotif-recette sont fermées (API de gestion) pour que la permission s'applique :
#      MédiNotif se reconnecte et reçoit ACCESS_REFUSED sur basic.consume, en boucle. Les messages restent
#      dans la file.
#   2. Limite de livraison retirée par Lucas (« delivery-limit: -1 » dans la Policy de la file), puis un
#      message EMPOISONNÉ (JSON imbriqué sur 100 000 niveaux : RecursionError dans json.loads, exception non
#      prévue par MédiNotif) est publié dans la file : MédiNotif plante, le message non acquitté revient,
#      MédiNotif replante (CrashLoopBackOff) ; sans limite de livraison, pour toujours. Le message porte
#      l'en-tête x-wb-panne: M27-E20. Rien n'est supprimé : à l'annulation, s'il est encore en tête, il est
#      rejeté sans remise en file, donc dead-letteré vers notifications.rebut.
#   3. Dans l'overlay recette de medinotif/deploiement, Lucas « harmonise » MEDINOTIF_FILE=notification
#      (sans s) : la file n'existe pas (MEDINOTIF_DECLARER_FILE=0), MédiNotif boucle sur NOT_FOUND.
# Réimport des définitions du vhost à l'annulation tant que la panne est encore en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_e20_sans_consommateur() { m27_rmq_file 2>/dev/null | jq -e '(.consumers // 1) == 0' >/dev/null 2>&1; }

# --- Variante 1 : permission de lecture retirée ------------------------------------------------------

_e20_v1_poser() {
  local lieu
  lieu="$(m27_rmq_permission_trouver "$_M27_U_NOTIF")" || return 10
  m27_rmq_modifier_doc E20 v1 "${lieu%%$'\t'*}" "${lieu##*$'\t'}" \
    '.spec.permissions.read = "^notifications\\.rebut$"' \
    "topologie recette : MédiNotif ne lit que ce dont il a besoin" || return $?
  m27_argo_rafraichir rabbitmq-topologie
}
_e20_v1_constat() {
  # La permission vivante (après Argo CD et le Topology Operator), puis les connexions fermées une fois.
  m27_rmq GET "permissions/$_M27_VHOST/$_M27_U_NOTIF" 2>/dev/null | jq -e '.read == "^notifications\\.rebut$"' >/dev/null 2>&1 || return 1
  if [[ -z "$(m27_lire E20 v1-ferme)" ]]; then
    m27_rmq DELETE "connections/username/$_M27_U_NOTIF" >/dev/null 2>&1 || true
    m27_ecrire E20 v1-ferme oui
    m27_journal E20 "connexions de $_M27_U_NOTIF fermées"
    return 1
  fi
  _e20_sans_consommateur
}
_e20_v1_defaire() {
  if m27_commit_actif E20 v1; then
    m27_retablir E20 v1 || true
    m27_rmq_reimporter E20
    m27_argo_rafraichir rabbitmq-topologie
  else
    m27_oublier E20 git-v1
  fi
  m27_oublier E20 v1-ferme
}

# --- Variante 2 : message empoisonné sans limite de livraison -------------------------------------

# _e20_permission_temporaire poser|retirer — le compte par défaut publie ou lit dans le vhost de recette le
# temps d'un geste (il n'y a aucune permission par défaut). Une permission préexistante n'est pas touchée.
_e20_permission_temporaire() {
  local admin
  admin="$(m27_rmq_admin_nom)" || return 1
  case "$1" in
    poser)
      if m27_rmq GET "permissions/$_M27_VHOST/$admin" >/dev/null 2>&1; then return 0; fi
      m27_rmq PUT "permissions/$_M27_VHOST/$admin" '{"configure":"^$","write":"^amq\\.default$","read":"^notifications$"}' >/dev/null || return 1
      m27_ecrire E20 v2-permission "$admin"
      ;;
    retirer)
      if [[ -n "$(m27_lire E20 v2-permission)" ]]; then
        m27_rmq DELETE "permissions/$_M27_VHOST/$admin" >/dev/null 2>&1 || true
        m27_oublier E20 v2-permission
      fi
      ;;
  esac
}

# _e20_redemarrages — total des redémarrages des conteneurs de MédiNotif (recette), d'après le sélecteur
# du Deployment « medinotif ».
_e20_redemarrages() {
  local sel
  sel="$(wb_kubectl -n "$_M27_NS_NOTIF" get deployment medinotif -o json 2>/dev/null |
    jq -r '.spec.selector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')" || return 1
  [[ -n "$sel" ]] || return 1
  wb_kubectl -n "$_M27_NS_NOTIF" get pods -l "$sel" -o json 2>/dev/null |
    jq '[.items[].status.containerStatuses[]?.restartCount // 0] | add // 0'
}

_e20_poison() {
  python3 -c 'import sys; n=100000; sys.stdout.write("[" * n + "]" * n)'
}

_e20_v2_poser() {
  local lieu q corps r
  q="$(m27_rmq_file)" || return 1
  # Une limite posée en argument de file (x-delivery-limit) ne se change pas par politique : variante inapplicable.
  jq -e '.arguments["x-delivery-limit"] == null' <<<"$q" >/dev/null || return 10
  # Sans rebut, le message empoisonné ne pourrait sortir qu'en étant supprimé : variante refusée.
  jq -e '(.arguments["x-dead-letter-exchange"] // .effective_policy_definition["dead-letter-exchange"] // "") != ""' <<<"$q" >/dev/null || return 10
  lieu="$(m27_rmq_politique_trouver)" || return 10
  m27_rmq_modifier_doc E20 v2 "${lieu%%$'\t'*}" "${lieu##*$'\t'}" \
    '.spec.definition["delivery-limit"] = -1' \
    "topologie recette : plus de limite de livraison (des notifications partaient au rebut)" || return $?
  m27_argo_rafraichir rabbitmq-topologie
  m27_attendre 300 _e20_v2_politique || return 1
  m27_ecrire E20 v2-redemarrages "$(_e20_redemarrages || echo 0)"
  _e20_permission_temporaire poser || return 1
  corps="$(_e20_poison | jq -Rsc '{properties: {delivery_mode: 2, content_type: "application/json", headers: {"x-wb-panne": "M27-E20"}},
     routing_key: "notifications", payload: ., payload_encoding: "string"}')"
  r="$(m27_rmq POST "exchanges/$_M27_VHOST/amq.default/publish" "$corps" 2>/dev/null)" ||
    r="$(m27_rmq PUT "exchanges/$_M27_VHOST/amq.default/publish" "$corps" 2>/dev/null)" || r=""
  _e20_permission_temporaire retirer
  jq -e '.routed == true' <<<"$r" >/dev/null 2>&1 || { wb_avert "publication du message de la panne refusée"; return 1; }
  m27_ecrire E20 v2-poison oui
  m27_journal E20 "limite de livraison retirée, message empoisonné publié"
}
_e20_v2_politique() {
  m27_rmq_file 2>/dev/null | jq -e '.effective_policy_definition["delivery-limit"] == -1' >/dev/null 2>&1
}
_e20_v2_constat() {
  _e20_v2_politique || return 1
  # MédiNotif a redémarré au moins deux fois depuis l'injection (plantage sur le message, puis de nouveau).
  local avant apres
  avant="$(m27_lire E20 v2-redemarrages)"
  apres="$(_e20_redemarrages)" || return 1
  ((apres >= ${avant:-0} + 2))
}
_e20_v2_defaire() {
  local tete
  if m27_commit_actif E20 v2; then
    m27_retablir E20 v2 || true
    m27_rmq_reimporter E20
    m27_argo_rafraichir rabbitmq-topologie
  else
    m27_oublier E20 git-v2
  fi
  if [[ -n "$(m27_lire E20 v2-poison)" ]]; then
    # Le message empoisonné, s'il est encore EN TÊTE (MédiNotif en attente de redémarrage), part au rebut :
    # rejet sans remise en file = dead-lettering (la file a un rebut, vérifié à l'injection).
    tete="$(m27_rmq_ctl rabbitmq-queues peek --vhost "$_M27_VHOST" "$_M27_FILE" 1 2>/dev/null | head -c 2000)" || tete=""
    # « get » prend le premier message DISPONIBLE : seulement quand aucun consommateur ne tient de message
    # (MédiNotif en attente de redémarrage), sinon on risquerait d'envoyer au rebut une vraie notification.
    # Dans le cas contraire, la limite de livraison rétablie ci-dessus l'y enverra d'elle-même.
    if grep -q '\[\[\[\[\[' <<<"$tete" &&
      m27_rmq_file 2>/dev/null | jq -e '(.consumers // 1) == 0 and (.messages_unacknowledged // 1) == 0' >/dev/null 2>&1; then
      _e20_permission_temporaire poser || true
      m27_rmq POST "queues/$_M27_VHOST/$_M27_FILE/get" '{"count":1,"ackmode":"reject_requeue_false","encoding":"auto","truncate":64}' >/dev/null 2>&1 || true
      _e20_permission_temporaire retirer
      m27_journal E20 "message empoisonné rejeté vers le rebut"
    else
      m27_journal E20 "message empoisonné absent de la tête de file (déjà au rebut, ou en cours de livraison) : rien à faire"
    fi
    m27_oublier E20 v2-poison
  fi
  m27_oublier E20 v2-redemarrages
}

# --- Variante 3 : nom de file faux dans MédiNotif -------------------------------------------------------

_e20_v3_poser() {
  local ops tmp
  ops="$(m27_patch_env "$_M27_NS_NOTIF" medinotif MEDINOTIF_FILE notification)" || return 10
  tmp="$(m27_etat E20)/tmp"
  mkdir -p "$tmp"
  m27_overlay_avec_patch "$_M27_DEPOT_NOTIF" '{"group":"apps","kind":"Deployment","name":"medinotif"}' "$ops" "$tmp/overlay.yaml" || return 10
  m27_commit E20 v3 "$_M27_DEPOT_NOTIF" "recette : nom de file harmonisé avec la documentation" \
    "$_M27_OVERLAY" "$tmp/overlay.yaml" || return 1
  m27_argo_rafraichir "$_M27_APP_NOTIF"
}
_e20_v3_constat() {
  m27_deploiement_a "$_M27_NS_NOTIF" medinotif \
    'any(.spec.template.spec.containers[].env[]?; .name == "MEDINOTIF_FILE" and .value == "notification")' &&
    _e20_sans_consommateur
}
_e20_v3_defaire() {
  if m27_commit_actif E20 v3; then
    m27_retablir E20 v3 || true
    m27_argo_rafraichir "$_M27_APP_NOTIF"
  else
    m27_oublier E20 git-v3
  fi
}

# --- Mécanique commune --------------------------------------------------------------------------------

_m27E20_une() {
  local n="$1" rc=0
  "_e20_v${n}_poser" || rc=$?
  if ((rc != 0)); then
    "_e20_v${n}_defaire" || true
    return "$rc"
  fi
  m27_debut E20
  if ! m27_attendre 480 "_e20_v${n}_constat"; then
    "_e20_v${n}_defaire" || true
    return 10
  fi
}

_e20_preparer() { m27_preparer messagerie && m27_rmq_exporter E20; }

panne_E20_v1() { _e20_preparer && m27_essayer E20 3 1; }
panne_E20_v2() { _e20_preparer && m27_essayer E20 3 2; }
panne_E20_v3() { _e20_preparer && m27_essayer E20 3 3; }

verifier_E20() {
  case "$WB_VAR" in
    1) m27_commit_actif E20 v1 && _e20_sans_consommateur ;;
    2) m27_commit_actif E20 v2 && _e20_v2_politique ;;
    3) m27_commit_actif E20 v3 && _e20_sans_consommateur ;;
    *) return 1 ;;
  esac
}

annuler_E20() {
  case "${WB_VAR:-}" in
    [1-3]) "_e20_v${WB_VAR}_defaire" ;;
    *) local v; for v in 1 2 3; do "_e20_v${v}_defaire" || true; done ;;
  esac
  m27_oublier E20 debut
  m27_oublier E20 tmp-v1
  m27_oublier E20 tmp-v2
  m27_oublier E20 tmp
  m27_journal E20 "annulation (définitions exportées conservées dans l'état local)"
}

resume_E20() {
  echo "En recette, MédiNotif n'envoie plus rien et la file notifications monte."
}

symptome_E20() {
  wb_symptome "Ticket INC-5420 — De : Julien Petit" \
    "En recette, plus aucune notification n'est envoyée depuis un moment. MédiAgenda dit qu'il publie," \
    "et la file « notifications » du vhost medinotif-recette ne fait que monter. On n'a rien livré côté" \
    "MédiNotif. Lucas a « rangé » des choses dans la messagerie ces derniers jours." \
    "Remets la consommation en route sans perdre un seul message, et fais passer ce qui s'est accumulé." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 27 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 27 E20 3 "$@"; }
fi
