# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# _m27-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 27
# (check-E19 à check-E25). Sourcé, jamais lancé seul ; charge _m27-production.sh. Lecture seule.
# Préfixe _m27x_ : évite les collisions quand check-E25 charge plusieurs checks.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m27x_journal=docs/kubernetes/journal
  _m27x_postmortems=docs/kubernetes/post-mortems
  _m27x_url_recette="${WB_M27_TRAFIC_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
}

# _m27x_temoin — le témoin de trafic du palier 4 tourne (créé à la première injection).
_m27x_temoin() {
  _m27p_kq '(.status.availableReplicas // 0) >= 1' -n wb-pannes deployment trafic-recette
}

# _m27x_creations_recentes [FENÊTRE] — des créations de rendez-vous réussies (201) en recette.
_m27x_creations_recentes() {
  _m27p_prom_positif "sum(increase(mediagenda_http_requests_total{namespace=\"$_m27p_recette\", methode=\"POST\", code=\"201\"}[${1:-10m}]))"
}

# _m27x_journal_inc NUMÉRO REGEX… — un journal de diagnostic de l'incident (nom contenant INC-NUMÉRO).
_m27x_journal_inc() {
  local n="$1"
  shift
  _m27p_doc "$_m27x_journal" "INC-$n" "$@"
}

# _m27x_pret_recette — /pret de MédiAgenda recette répond 200.
_m27x_pret_recette() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$_m27x_url_recette/pret" 2>/dev/null)" || code=""
  [[ "$code" == 200 ]]
}

# _m27x_medinotif_sain ESPACE — Deployment medinotif disponible (au moins 1), aucun conteneur en attente
# d'un redémarrage (CrashLoopBackOff) ni redémarré dans les 10 dernières minutes.
_m27x_medinotif_sain() {
  local sel
  _m27p_kq '(.status.availableReplicas // 0) >= 1 and (.status.updatedReplicas // 0) == (.spec.replicas // 1)' -n "$1" deployment medinotif || return 1
  sel="$(kube -n "$1" get deployment medinotif -o json 2>/dev/null |
    jq -r '.spec.selector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')" || return 1
  [[ -n "$sel" ]] || return 1
  kube -n "$1" get pods -l "$sel" -o json 2>/dev/null | jq -e '
    [.items[].status.containerStatuses[]?
     | select((.state.waiting.reason // "") == "CrashLoopBackOff"
              or (((.lastState.terminated.finishedAt // "1970-01-01T00:00:00Z") | fromdateiso8601) > (now - 600)))]
    | length == 0' >/dev/null 2>&1
}

# _m27x_file_saine VHOST — la file notifications a un consommateur, moins de 20 messages prêts et ne
# redélivre pas en boucle.
_m27x_file_saine() {
  _m27p_file "$1" notifications '(.consumers // 0) >= 1 and (.messages_ready // 0) < 20
    and ((.message_stats.redeliver_details.rate // 0) < 0.2)'
}

# _m27x_file_protegee VHOST — la file a un rebut et une limite de livraison (défaut 20 si rien n'est posé ;
# -1 = sans limite).
_m27x_file_protegee() {
  _m27p_file "$1" notifications '
    ((.arguments["x-dead-letter-exchange"] // .effective_policy_definition["dead-letter-exchange"] // "") != "")
    and ((.arguments["x-delivery-limit"] // .effective_policy_definition["delivery-limit"] // 20) | tonumber > 0)'
}
