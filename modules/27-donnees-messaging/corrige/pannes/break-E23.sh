# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions yq entre apostrophes
# break-E23.sh — M27-E23 « Astreinte : des rendez-vous sans notification » (RECETTE, scénario unique)
#
# Panne EN CHAÎNE, trois commits de Lucas, posés dans cet ordre (définitions exportées avant) :
#   L1. Topologie (plateforme/donnees) : la Permission de l'utilisateur de publication mediagenda-recette
#       passe en write « ^notification$ » (faute de frappe) ; ses connexions sont fermées pour que la
#       permission s'applique. MédiAgenda publie sur l'échange « notifications » : ACCESS_REFUSED, la
#       publication échoue, la requête réussit quand même (comportement voulu de M27-E08) : silencieux.
#   L2. medinotif/deploiement, overlay recette : MédiNotif à zéro réplica (« en attendant KEDA »).
#   L3. Topologie : la Policy de la file notifications reçoit message-ttl 60000 (« une notification de
#       plus d'une minute est périmée ») : un message non consommé en 60 s EXPIRE et part au rebut
#       (x-death reason « expired »). La stratégie de rebut reste celle de M27-E04 : dead-letter-strategy
#       at-least-once avec overflow reject-publish (vérifiés avant ; sinon L3 n'est PAS posée). Le transfert
#       vers notifications.rebut est donc confirmé : aucun message n'est perdu.
#       Décision de relecture (bloc G) : PAS de max-length avec overflow drop-head. drop-head fait retomber le
#       rebut en « au plus une fois », et passer overflow de reject-publish à drop-head SUPPRIME les messages
#       dead-letterés pas encore confirmés (documentation des files quorum) : c'est un mode qui perd des
#       messages, interdit par PLAN §4.13.
# Ce que voit l'apprenant : rien ne part. Corriger L1 fait arriver les messages… qui ne restent pas dans la
# file (L2 : personne ne consomme) et partent au rebut une minute plus tard (L3). Corriger L2 fait repartir
# la consommation, mais ce qui a expiré est au rebut et la TTL reste un piège latent : il faut la retirer et
# rejouer le rebut. Aucune purge ; l'annulation défait les commits encore en place et laisse le contenu du
# rebut (à rejouer par l'apprenant ; le nombre de messages au rebut avant l'injection est noté pour le check).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_e23_publie_total() {
  m27_rmq GET "exchanges/$_M27_VHOST/$_M27_FILE" 2>/dev/null | jq -r '.message_stats.publish_in // 0'
}

_e23_l1() {
  local lieu
  lieu="$(m27_rmq_permission_trouver "$_M27_U_AGENDA")" || { wb_avert "Permission de $_M27_U_AGENDA introuvable dans $_M27_TOPOLOGIE"; return 1; }
  m27_rmq_modifier_doc E23 l1 "${lieu%%$'\t'*}" "${lieu##*$'\t'}" \
    '.spec.permissions.write = "^notification$"' \
    "topologie recette : MédiAgenda ne publie que sur son échange" || return 1
}
_e23_l1_vivant() {
  m27_rmq GET "permissions/$_M27_VHOST/$_M27_U_AGENDA" 2>/dev/null | jq -e '.write == "^notification$"' >/dev/null 2>&1
}

_e23_l2() {
  local tmp
  tmp="$(m27_etat E23)/tmp"
  mkdir -p "$tmp"
  m27_overlay_avec_patch "$_M27_DEPOT_NOTIF" '{"group":"apps","kind":"Deployment","name":"medinotif"}' \
    '[{"op":"add","path":"/spec/replicas","value":0}]' "$tmp/overlay.yaml" || return 1
  m27_commit E23 l2 "$_M27_DEPOT_NOTIF" "recette : MédiNotif à zéro en attendant KEDA (économie de ressources)" \
    "$_M27_OVERLAY" "$tmp/overlay.yaml" || return 1
}
_e23_l2_vivant() { m27_deploiement_a "$_M27_NS_NOTIF" medinotif '.spec.replicas == 0'; }

_e23_l3() {
  local lieu q
  q="$(m27_rmq_file)" || return 1
  # Rebut présent ET transfert confirmé (at-least-once, qui exige overflow reject-publish) ; aucune TTL ni
  # limite posée en argument de file (une politique ne pourrait pas être annulée proprement).
  if ! jq -e '(.arguments["x-dead-letter-exchange"] // .effective_policy_definition["dead-letter-exchange"] // "") != ""
      and ((.arguments["x-dead-letter-strategy"] // .effective_policy_definition["dead-letter-strategy"] // "") == "at-least-once")
      and ((.arguments["x-overflow"] // .effective_policy_definition["overflow"] // "") == "reject-publish")
      and (.arguments["x-message-ttl"] == null)' <<<"$q" >/dev/null; then
    m27_journal E23 "L3 non posée : rebut absent ou non « at-least-once » (des messages pourraient être perdus)"
    return 0
  fi
  # Le rebut ne doit avoir AUCUNE durée de vie : un message qui y expirerait serait renvoyé vers le même
  # échange de rebut (cycle : RabbitMQ le supprime) ou détruit. On exige donc qu'aucune TTL n'y soit déjà
  # en vigueur et que la Policy visée ne s'applique pas à la file de rebut (motif « ^notifications »…).
  if ! m27_rmq_file "$_M27_REBUT" 2>/dev/null | jq -e '(.effective_policy_definition["message-ttl"] // .arguments["x-message-ttl"]) == null' >/dev/null; then
    m27_journal E23 "L3 non posée : la file de rebut est introuvable ou a déjà une durée de vie"
    return 0
  fi
  lieu="$(m27_rmq_politique_trouver)" || { m27_journal E23 "L3 non posée : aucune Policy de la file dans la topologie"; return 0; }
  if m27_gl_fichier "$_M27_DEPOT_DONNEES" "${lieu%%$'\t'*}" 2>/dev/null |
    IDX="${lieu##*$'\t'}" yq -o=json -I=0 'select(documentIndex == (strenv(IDX) | to_number)) | .spec.pattern' 2>/dev/null |
    jq -e --arg r "$_M27_REBUT" '. as $p | $r | test($p)' >/dev/null 2>&1; then
    m27_journal E23 "L3 non posée : la Policy de la file s'applique aussi au rebut (une TTL y perdrait des messages)"
    return 0
  fi
  m27_rmq_modifier_doc E23 l3 "${lieu%%$'\t'*}" "${lieu##*$'\t'}" \
    '.spec.definition["message-ttl"] = 60000' \
    "topologie recette : notifications périmées après une minute (pas d'envoi en retard)" || return 1
}
_e23_l3_vivant() {
  [[ -d "$(m27_etat E23)/git-l3" ]] || return 0   # L3 non posée (pas de rebut sûr ou pas de Policy)
  m27_rmq_file 2>/dev/null | jq -e '.effective_policy_definition["message-ttl"] == 60000
    and .effective_policy_definition["dead-letter-strategy"] == "at-least-once"
    and .effective_policy_definition["overflow"] == "reject-publish"' >/dev/null 2>&1 || return 1
  # Contrôle de sûreté sur place : le rebut, lui, n'a toujours aucune durée de vie.
  m27_rmq_file "$_M27_REBUT" 2>/dev/null | jq -e '(.effective_policy_definition["message-ttl"] // .arguments["x-message-ttl"]) == null' >/dev/null 2>&1
}

_e23_tout_vivant() {
  _e23_l1_vivant && _e23_l2_vivant && _e23_l3_vivant || return 1
  if [[ -z "$(m27_lire E23 l1-ferme)" ]]; then
    m27_rmq DELETE "connections/username/$_M27_U_AGENDA" >/dev/null 2>&1 || true
    m27_ecrire E23 l1-ferme oui
    m27_ecrire E23 publie-avant "$(_e23_publie_total)"
    m27_ecrire E23 ferme-a "$(date +%s)"
    m27_journal E23 "connexions de $_M27_U_AGENDA fermées"
    return 1
  fi
}

# Constat : depuis la fermeture des connexions, plus rien n'est publié sur l'échange alors que le témoin
# crée un rendez-vous toutes les 10 s (au moins deux minutes d'observation).
_e23_constat() {
  local avant apres t
  _e23_tout_vivant || return 1
  t="$(m27_lire E23 ferme-a)"
  (($(date +%s) >= ${t:-0} + 120)) || return 1
  avant="$(m27_lire E23 publie-avant)"
  apres="$(_e23_publie_total)"
  [[ "$apres" == "${avant:-x}" ]]
}

panne_E23_v1() {
  m27_preparer messagerie || return 1
  m27_rmq_exporter E23 || return 1
  m27_ecrire E23 rebut-avant "$(m27_rmq_file "$_M27_REBUT" 2>/dev/null | jq -r '.messages // 0')"
  _e23_l1 || { annuler_E23; return 1; }
  _e23_l2 || { annuler_E23; return 1; }
  _e23_l3 || { annuler_E23; return 1; }
  m27_argo_rafraichir rabbitmq-topologie "$_M27_APP_NOTIF"
  m27_debut E23
  m27_journal E23 "chaîne posée (L1 permission, L2 MédiNotif à zéro, L3 TTL d'une minute)"
  if ! m27_attendre 600 _e23_constat; then
    annuler_E23
    return 1
  fi
}

verifier_E23() {
  m27_commit_actif E23 l1 && m27_commit_actif E23 l2
}

annuler_E23() {
  local actif=0 c
  for c in l1 l3; do m27_commit_actif E23 "$c" && actif=1; done
  for c in l1 l2 l3; do
    if m27_commit_actif E23 "$c"; then m27_retablir E23 "$c" || true; else m27_oublier E23 "git-$c"; fi
  done
  # Définitions du vhost réimportées seulement si une panne de topologie était encore en place.
  if ((actif)); then m27_rmq_reimporter E23; fi
  m27_argo_rafraichir rabbitmq-topologie "$_M27_APP_NOTIF"
  m27_oublier E23 l1-ferme
  m27_oublier E23 publie-avant
  m27_oublier E23 ferme-a
  m27_oublier E23 debut
  m27_oublier E23 tmp
  m27_oublier E23 tmp-l1
  m27_oublier E23 tmp-l3
  m27_journal E23 "annulation : messages éventuels du rebut laissés en place (à rejouer, RB-277)"
}

resume_E23() {
  echo "Des rendez-vous de recette sont confirmés sans qu'aucune notification ne parte."
}

symptome_E23() {
  wb_symptome "Ticket INC-5423 — De : Nadia Roussel, 6 h 52" \
    "Le centre pilote de la recette élargie appelle : des patients ont pris rendez-vous hier soir et ce" \
    "matin, aucun n'a reçu de confirmation. Côté prise de rendez-vous, tout est vert ; aucune alerte ne m'a" \
    "réveillée cette nuit. Lucas a poussé « quelques réglages » sur la messagerie et MédiNotif hier." \
    "Je te confie l'incident : un point toutes les 30 minutes, les notifications manquantes envoyées sans" \
    "doublon, et un post-mortem." \
    "" \
    "Temps cible : 1 h 30. Contrôle : lab/bin/check 27 23"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 27 E23 1 "$@"; }
fi
