# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts entre apostrophes
# break-S13.sh — F3-S13 « Vendredi : les notifications s'accumulent » (INC-5913)
#
# PRODUCTION (vhost medinotif-prod, espace medinotif-prod) : seulement des pannes de capacité ou de
# configuration réversibles, AUCUNE perte de message (PLAN §4.13 « Pannes du bloc G ») :
#   - avant tout : export des définitions de la grappe et du vhost (état local, 600 : copie de secours) ;
#   - jamais de purge, jamais de suppression de file ni de message, jamais de mode qui perd des
#     messages ; un message qui doit sortir d'une file part au rebut (notifications.rebut) ;
#   - la charge : une « campagne de rappels » factice publiée par l'API de gestion depuis adm01
#     (processus d'arrière-plan borné : WB_F3_S13_DEBIT messages/s, WB_F3_S13_DUREE s au plus, arrêté
#     par --annuler). Messages VALIDES (SMS vers +33600000000, modèle rappel-veille, en-tête
#     x-wb-panne: F3-S13) : MédiNotif les « envoie » (simulation : une ligne de journal), rien ne part.
#     Débit par défaut 110/s : au-dessus de 4 pods (≈ 80/s, repli de KEDA) et de 2 pods (≈ 40/s), en
#     dessous de 8 pods (≈ 160/s, mesures de M28-E13 : 6 pods ≈ 120/s).
# Variantes :
#   1. compte keda-prod « désynchronisé » : son mot de passe est EFFACÉ dans RabbitMQ
#      (rabbitmqctl clear_password) ; OpenBao, le Secret de l'espace et le TriggerAuthentication
#      gardent l'ancien. Le scaler rabbitmq reçoit 401, KEDA passe en repli (fallback : 4 pods) ;
#   2. ScaledObject medinotif modifié EN DIRECT (la prod est synchronisée à la main par Argo CD : la
#      dérive reste) : maxReplicaCount ramené au minimum (2) ;
#   3. message empoisonné sans rebut : une politique RabbitMQ « notifications-maintenance » de priorité
#      20 (au-dessus de notifications-rebut, priorité 10 : une seule politique s'applique) recopie la
#      définition effective avec delivery-limit: -1, puis un message empoisonné (JSON imbriqué sur
#      100 000 niveaux : RecursionError, exception non prévue par MédiNotif, M27-E20) est publié : le
#      consommateur qui le reçoit plante, le message revient, pour toujours. Débit de la campagne :
#      2 messages/s seulement (la file grossit parce que plus rien ne consomme).
# Annulation (idempotente) : campagne arrêtée (les messages déjà publiés restent et seront consommés),
# mot de passe de keda-prod remis depuis le Secret de la topologie (si keda-prod ne s'authentifie plus),
# ScaledObject restauré, politique de maintenance supprimée (le message empoisonné atteint la limite de
# livraison 5 et part au rebut, at-least-once). Accès : kubeconfig d'administration (Secrets
# messagerie/rabbitmq-default-user, messagerie/rabbitmq-utilisateur-keda-prod et
# medinotif-prod/medinotif-rabbitmq lus en mémoire, jamais affichés), API de gestion de RabbitMQ.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-fin-pannes.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-fin-pannes.sh"

_S13_NS=medinotif-prod
_S13_NS_MSG=messagerie
_S13_VHOST=medinotif-prod
_S13_FILE=notifications
_S13_SO=medinotif
_S13_UTIL_KEDA=keda-prod
_S13_POL_MAINT=notifications-maintenance
_S13_RMQ_POD=rabbitmq-server-0
_S13_URL="${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}"
_S13_DEBIT="${WB_F3_S13_DEBIT:-110}"
_S13_DUREE="${WB_F3_S13_DUREE:-2700}"

# --- RabbitMQ : compte par défaut de l'opérateur (bris de glace), jamais affiché ----------------------
_s13_secret_val() { # ESPACE SECRET CLÉ
  wb_kubectl -n "$1" get secret "$2" -o json 2>/dev/null | jq -r --arg k "$3" '.data[$k] // empty | @base64d'
}
_s13_cfg_admin() {
  local u p
  u="$(_s13_secret_val "$_S13_NS_MSG" rabbitmq-default-user username)"
  p="$(_s13_secret_val "$_S13_NS_MSG" rabbitmq-default-user password)"
  [[ -n "$u" && -n "$p" ]] || return 1
  printf 'user = "%s:%s"\n' "$u" "$p"
}
# _s13_rmq MÉTHODE CHEMIN [-] — API de gestion ; avec « - », corps JSON lu sur l'entrée standard.
_s13_rmq() {
  local m="$1" chemin="$2" cfg
  cfg="$(_s13_cfg_admin)" || { wb_avert "compte par défaut de RabbitMQ illisible ($_S13_NS_MSG/rabbitmq-default-user)"; return 1; }
  if [[ "${3:-}" == - ]]; then
    curl -sf --max-time 30 -X "$m" -H "Content-Type: application/json" --data-binary @- \
      -K <(printf '%s\n' "$cfg") "$_S13_URL/api/$chemin"
  else
    curl -sf --max-time 30 -X "$m" -K <(printf '%s\n' "$cfg") -H "Accept: application/json" "$_S13_URL/api/$chemin"
  fi
}
_s13_file() { _s13_rmq GET "queues/$_S13_VHOST/$_S13_FILE" 2>/dev/null || true; }
# _s13_keda_authentifie — keda-prod s'authentifie avec le mot de passe que voit KEDA (Secret de l'espace).
_s13_keda_authentifie() {
  local u p
  u="$(_s13_secret_val "$_S13_NS" medinotif-rabbitmq utilisateur)"
  p="$(_s13_secret_val "$_S13_NS" medinotif-rabbitmq mot_de_passe)"
  [[ -n "$u" && -n "$p" ]] || return 1
  curl -sf --max-time 10 -o /dev/null -K <(printf 'user = "%s:%s"\n' "$u" "$p") "$_S13_URL/api/whoami"
}
_s13_maintenance_active() {
  _s13_file | jq -e --arg p "$_S13_POL_MAINT" '.policy == $p and .effective_policy_definition["delivery-limit"] == -1' >/dev/null 2>&1
}
_s13_consomme() { _s13_file | jq -e '(.consumers // 0) >= 2' >/dev/null 2>&1; }
_s13_so() { wb_kubectl -n "$_S13_NS" get scaledobjects.keda.sh "$_S13_SO" -o json 2>/dev/null || true; }

# --- Campagne factice (arrière-plan, bornée) ---------------------------------------------------------------
_s13_campagne_lancer() {
  local debit="$1" d script
  d="$(f3fp_etat S13)"
  rm -f -- "$d/campagne.arret"
  printf '%s' '{"type":"sms","destinataire":"+33600000000","modele":"rappel-veille","rendez_vous_id":905913}' |
    jq -Rc --arg f "$_S13_FILE" '{properties: {delivery_mode: 2, content_type: "application/json", headers: {"x-wb-panne": "F3-S13"}},
             routing_key: $f, payload: ., payload_encoding: "string"}' >"$d/corps.json"
  script="$d/campagne.sh"
  cat >"$script" <<'CAMPAGNE'
#!/usr/bin/env bash
# Campagne factice de F3-S13 : publie DEBIT messages/s par l'API de gestion, jusqu'à FIN ou au fichier d'arrêt.
set -u
d="$1" debit="$2" duree="$3" url="$4" kcfg="$5"
fin=$(( $(date +%s) + duree ))
s="$(kubectl --kubeconfig "$kcfg" -n messagerie get secret rabbitmq-default-user -o json 2>/dev/null)" || exit 1
u="$(jq -r '.data.username | @base64d' <<<"$s")"; p="$(jq -r '.data.password | @base64d' <<<"$s")"; s=""
u="${u//\\/\\\\}"; u="${u//\"/\\\"}"; p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
echo "$$" > "$d/campagne.pid"
while (( $(date +%s) < fin )) && [[ ! -e "$d/campagne.arret" ]]; do
  t0=$(date +%s%N)
  for ((i = 0; i < debit; i++)); do
    printf 'url = "%s/api/exchanges/medinotif-prod/amq.default/publish"\nrequest = "POST"\nheader = "Content-Type: application/json"\ndata-binary = "@%s/corps.json"\nuser = "%s:%s"\noutput = "/dev/null"\nmax-time = 10\nnext\n' \
      "$url" "$d" "$u" "$p"
  done | curl -s --parallel --parallel-max 12 -K - >/dev/null 2>&1
  t1=$(date +%s%N); reste=$(( 1000000000 - (t1 - t0) ))
  (( reste > 0 )) && sleep "0.$(printf '%09d' "$reste")"
done
rm -f "$d/campagne.pid"
CAMPAGNE
  chmod 700 "$script"
  setsid nohup bash "$script" "$d" "$debit" "$_S13_DUREE" "$_S13_URL" "${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}" \
    >/dev/null 2>&1 </dev/null &
  f3fp_attendre 20 test -s "$d/campagne.pid" || { wb_avert "la campagne factice n'a pas démarré"; return 1; }
  f3fp_journal S13 "campagne factice lancée : $debit messages/s pendant $_S13_DUREE s au plus"
}
_s13_campagne_arreter() {
  local d p
  d="$(f3fp_etat S13)"
  : >"$d/campagne.arret"
  p="$(cat "$d/campagne.pid" 2>/dev/null || true)"
  if [[ "$p" =~ ^[0-9]+$ ]] && grep -q 'campagne.sh' "/proc/$p/cmdline" 2>/dev/null; then
    kill "$p" 2>/dev/null || true
  fi
  rm -f -- "$d/campagne.pid" "$d/corps.json"
}

# --- Contrôle préalable -------------------------------------------------------------------------------------
_s13_sain() {
  local q so d
  f3fp_preparer S13 setsid python3 || return 1
  q="$(_s13_file)"
  jq -e '.type == "quorum" and (.consumers // 0) >= 2 and (.messages // 0) < 1000
         and (.policy // "") != "" and ((.effective_policy_definition["delivery-limit"] // 20) > 0)
         and (.effective_policy_definition["dead-letter-exchange"] // "") != ""' >/dev/null 2>&1 <<<"$q" ||
    { f3fp_refus "file $_S13_VHOST/$_S13_FILE pas dans l'état attendu (quorum, ≥ 2 consommateurs, < 1000 messages, rebut actif)"; return 1; }
  so="$(_s13_so)"
  f3fp_condition "$so" Ready || { f3fp_refus "ScaledObject $_S13_SO pas Ready dans $_S13_NS (M28-E13)"; return 1; }
  f3fp_condition "$so" Fallback True && { f3fp_refus "ScaledObject $_S13_SO déjà en repli (fallback)"; return 1; }
  jq -e '.spec.maxReplicaCount > .spec.minReplicaCount' >/dev/null 2>&1 <<<"$so" ||
    { f3fp_refus "ScaledObject $_S13_SO : maxReplicaCount pas au-dessus du minimum"; return 1; }
  _s13_keda_authentifie || { f3fp_refus "keda-prod ne s'authentifie déjà plus auprès de RabbitMQ"; return 1; }
  # Copie de secours des définitions (avant toute injection, une seule fois).
  d="$(f3fp_etat S13)"
  if [[ ! -s "$d/definitions-vhost.json" ]]; then
    (umask 077 && _s13_rmq GET definitions >"$d/definitions-grappe.json" &&
      _s13_rmq GET "definitions/$_S13_VHOST" >"$d/definitions-vhost.json") ||
      { rm -f -- "$d"/definitions-*.json; f3fp_refus "export des définitions de RabbitMQ impossible : rien n'est cassé"; return 1; }
  fi
}

panne_S13_v1() {
  _s13_sain || return 1
  wb_kubectl -n "$_S13_NS_MSG" exec "$_S13_RMQ_POD" -c rabbitmq -- rabbitmqctl clear_password "$_S13_UTIL_KEDA" >/dev/null || return 1
  f3fp_journal S13 "mot de passe de $_S13_UTIL_KEDA effacé dans RabbitMQ"
  _s13_campagne_lancer "$_S13_DEBIT"
}

panne_S13_v2() {
  local min
  _s13_sain || return 1
  min="$(_s13_so | jq -r '.spec.minReplicaCount // 2')"
  wb_k8s_sauver scaledobjects.keda.sh "$_S13_SO" "$_S13_NS"
  wb_kubectl -n "$_S13_NS" patch scaledobjects.keda.sh "$_S13_SO" --type=merge -p "{\"spec\":{\"maxReplicaCount\":$min}}" >/dev/null || return 1
  f3fp_journal S13 "ScaledObject $_S13_SO : maxReplicaCount = $min (modifié en direct)"
  _s13_campagne_lancer "$_S13_DEBIT"
}

panne_S13_v3() {
  local q def
  _s13_sain || return 1
  q="$(_s13_file)"
  def="$(jq -c '.effective_policy_definition | .["delivery-limit"] = -1' <<<"$q")"
  jq -nc --arg p "^${_S13_FILE}\$" --argjson d "$def" '{pattern: $p, definition: $d, priority: 20, "apply-to": "quorum_queues"}' |
    _s13_rmq PUT "policies/$_S13_VHOST/$_S13_POL_MAINT" - >/dev/null || return 1
  f3fp_ecrire S13 politique "$_S13_POL_MAINT"
  f3fp_journal S13 "politique $_S13_POL_MAINT (priorité 20, delivery-limit -1) posée"
  sleep 3
  # Message empoisonné : 100 000 niveaux d'imbrication (≈ 200 Kio), corps par l'entrée standard.
  python3 -c 'import json,sys; print(json.dumps({"properties": {"delivery_mode": 2, "headers": {"x-wb-panne": "F3-S13"}},
    "routing_key": sys.argv[1], "payload": "[" * 100000 + "]" * 100000, "payload_encoding": "string"}))' "$_S13_FILE" |
    _s13_rmq POST "exchanges/$_S13_VHOST/amq.default/publish" - >/dev/null || return 1
  f3fp_journal S13 "message empoisonné publié dans $_S13_VHOST/$_S13_FILE"
  _s13_campagne_lancer 2
}

verifier_S13() {
  case "$WB_VAR" in
    1) ! _s13_keda_authentifie ;;
    2) _s13_so | jq -e '.spec.maxReplicaCount == .spec.minReplicaCount' >/dev/null 2>&1 ;;
    3) f3fp_attendre 30 _s13_maintenance_active ;;
    *) return 1 ;;
  esac
}

annuler_S13() {
  local u p d
  _s13_campagne_arreter
  # Variante 1 : mot de passe remis depuis le Secret de la topologie, si keda-prod ne s'authentifie plus.
  if ! _s13_keda_authentifie; then
    u="$(_s13_secret_val "$_S13_NS_MSG" rabbitmq-utilisateur-keda-prod username)"
    p="$(_s13_secret_val "$_S13_NS_MSG" rabbitmq-utilisateur-keda-prod password)"
    if [[ -n "$u" && -n "$p" ]]; then
      jq -nc --arg p "$p" '{password: $p, tags: "management"}' | _s13_rmq PUT "users/$u" - >/dev/null ||
        wb_avert "mot de passe de $u non remis : relance la réconciliation du User keda-prod (Messaging Topology Operator)"
    fi
    p=""
    _s13_keda_authentifie || wb_avert "keda-prod ne s'authentifie toujours pas (Secret de l'espace différent de celui de la topologie ? RB de rotation)"
  fi
  # Variante 2 : ScaledObject.
  wb_k8s_restaurer || wb_avert "ScaledObject $_S13_SO non restauré : synchronise l'Application de MédiNotif prod (Argo CD)"
  # Variante 3 : politique de maintenance supprimée (jamais la politique de rebut).
  if [[ -n "$(f3fp_lire S13 politique)" ]]; then
    _s13_rmq DELETE "policies/$_S13_VHOST/$_S13_POL_MAINT" >/dev/null 2>&1 || true
    f3fp_oublier S13 politique
    f3fp_attendre 180 _s13_consomme ||
      wb_avert "MédiNotif ne consomme pas encore : le message empoisonné doit partir au rebut à la 5e livraison (RB-277)"
  fi
  d="$(f3fp_etat S13)"
  wb_avert "copie des définitions de RabbitMQ conservée dans $d (à supprimer après vérification)"
  f3fp_journal S13 "annulation (aucun message supprimé)"
}

symptome_S13() {
  _f3p_symptome S13 INC-5913 "INC-5913 — Vendredi 10 h 20 — De : Nadia Roussel (support)" \
    "« Trois cabinets appellent : leurs patients n'ont pas reçu les SMS de rappel de ce matin." \
    "Dans l'interface de RabbitMQ, la file notifications de la prod grossit à vue d'œil. On a" \
    "pourtant mis KEDA pour ça, non ? » (une campagne de rappels exceptionnelle est en cours)" \
    "" \
    "Aucune notification ne doit être perdue." \
    "Temps cible : 45 min."
}

resume_S13() { echo "La file notifications de la production grossit, MédiNotif ne suit pas"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S13 3 "$@"; }
fi
