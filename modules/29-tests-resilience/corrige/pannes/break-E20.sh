# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E20.sh — M29-E20 « Panne : une expérience de chaos ne s'arrête plus » (recette)
#
# Toutes les expériences visent les pods de l'API MédiAgenda de mediagenda-recette (latence de 300 ms
# sur tout ce qu'ils émettent), ont une durée, et sont supprimées par --annuler, qui vérifie ensuite
# sur les nœuds qu'aucun qdisc netem ne reste (et le retire à la main en dernier recours).
#   1. Schedule « controle-latence » (chaos-experiences, */5 min, Forbid) qui embarque une NetworkChaos
#      de 90 min : Lucas a supprimé « l'expérience » (l'enfant), le Schedule la recrée au tick suivant ;
#   2. NetworkChaos « diagnostic-latence » (30 min) injectée, puis commit de Lucas dans plateforme/gitops
#      (valeurs/chaos-mesh/values.yaml : chaosDaemon.socketPath vers un socket inexistant) : les
#      chaos-daemon ne joignent plus containerd ; l'expérience, supprimée, reste bloquée sur son
#      finaliseur et le netem reste dans les pods ;
#   3. NetworkChaos « diagnostic-reseau » (48 h, chaos-experiences) que Lucas croit en pause : il a posé
#      l'annotation « chaos-mesh.org/pause: "true" » (le préfixe de l'annotation des ESPACES,
#      chaos-mesh.org/inject) au lieu de « experiment.chaos-mesh.org/pause » : le contrôleur l'ignore.
#      (Une expérience hors de chaos-experiences est impossible : la ValidatingAdmissionPolicy
#      medisphere-chaos-espaces de M29-E09 la refuse, administrateurs compris.)

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m29-commun.sh
source "$WB_ROOT/modules/29-tests-resilience/corrige/pannes/_m29-commun.sh"

_E20_GITOPS="${WB_M29_PROJET_GITOPS:-plateforme/gitops}"
_E20_VALEURS="${WB_M29_FICHIER_VALEURS_CHAOS:-valeurs/chaos-mesh/values.yaml}"
_E20_SOCKET_FAUX=/run/containerd/containerd-ancien.sock

# _e20_netem NOM DURÉE ESPACE [pause|fausse-pause] — manifeste d'une NetworkChaos de latence sur l'API
# de recette ; « fausse-pause » pose une annotation de pause à la mauvaise clé (variante 3).
_e20_netem() {
  cat <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: $1
  namespace: $3
  labels:
    medisphere.internal/auteur: lucas.martin
  annotations:
    medisphere.internal/hypothese: "Mesurer la latence ressentie par Julien (Lucas)"
$( [[ "${4:-}" == pause ]] && printf '    experiment.chaos-mesh.org/pause: "true"\n' )
$( [[ "${4:-}" == fausse-pause ]] && printf '    chaos-mesh.org/pause: "true"\n' )
spec:
  action: delay
  mode: all
  selector:
    namespaces: [$_M29_RECETTE]
    labelSelectors:
      app.kubernetes.io/name: mediagenda
      app.kubernetes.io/component: api
  direction: to
  delay:
    latency: 300ms
    jitter: 20ms
  duration: $2
EOF
}

_e20_schedule() {
  cat <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: controle-latence
  namespace: $_M29_CHAOS_NS
  labels:
    medisphere.internal/auteur: lucas.martin
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  historyLimit: 2
  startingDeadlineSeconds: 120
  type: NetworkChaos
  networkChaos:
    action: delay
    mode: all
    selector:
      namespaces: [$_M29_RECETTE]
      labelSelectors:
        app.kubernetes.io/name: mediagenda
        app.kubernetes.io/component: api
    direction: to
    delay:
      latency: 300ms
      jitter: 20ms
    duration: 90m
EOF
}

# _e20_un_netem — au moins un pod de l'API porte un netem.
_e20_un_netem() {
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && m29_netem_present "$_M29_RECETTE" "$p" && return 0
  done < <(m29_api_pods)
  return 1
}

# _e20_enfants — NetworkChaos créées par le Schedule (ownerReferences).
_e20_enfants() {
  wb_kubectl -n "$_M29_CHAOS_NS" get networkchaos -o json 2>/dev/null |
    jq -r '.items[] | select(any(.metadata.ownerReferences[]?; .kind == "Schedule" and .name == "controle-latence")) | .metadata.name'
}

_e20_daemon_casse() {
  wb_kubectl -n chaos-mesh get ds chaos-daemon -o json 2>/dev/null |
    jq -e --arg s "/host-run/$(basename "$_E20_SOCKET_FAUX")" '[.spec.template.spec.containers[].args[]?] | index($s) != null' >/dev/null 2>&1
}
_e20_daemon_bon() {
  wb_kubectl -n chaos-mesh get ds chaos-daemon -o json 2>/dev/null |
    jq -e --arg s "/host-run/$(basename "$_E20_SOCKET_FAUX")" '([.spec.template.spec.containers[].args[]?] | index($s) == null)
      and .status.numberReady == .status.desiredNumberScheduled and .status.updatedNumberScheduled == .status.desiredNumberScheduled' >/dev/null 2>&1
}

_e20_sain() {
  m29_outils ssh || return 1
  if ! m29_chaos_sain; then
    echo "Chaos Mesh n'est pas sain (contrôleur, daemons, annotation de $_M29_RECETTE) : répare d'abord (lab/bin/check 29 09)." >&2
    return 1
  fi
  if (($(m29_api_pretes) < 1)); then
    echo "Aucun pod prêt de l'API MédiAgenda en recette : rien n'est cassé, répare d'abord." >&2
    return 1
  fi
  if _e20_un_netem; then
    echo "Un netem est déjà posé sur un pod de l'API en recette : termine l'expérience en cours avant (RB-294)." >&2
    return 1
  fi
}

_m29E20_une() {
  local n="$1" e i tmp
  m29_poser E20 objets ""
  case "$n" in
    1)
      _e20_schedule | wb_kubectl apply -f - >/dev/null || return 1
      m29_poser E20 objets "$_M29_CHAOS_NS schedule controle-latence"
      # Le premier tick arrive dans 5 min au plus ; on attend l'enfant et son injection.
      m29_attendre 420 _e20_un_netem || return 10
      # Lucas « supprime l'expérience » : l'enfant, pas le Schedule.
      while IFS= read -r e; do
        [[ -n "$e" ]] && wb_kubectl -n "$_M29_CHAOS_NS" delete networkchaos "$e" --wait=false >/dev/null 2>&1
      done < <(_e20_enfants)
      m29_journal E20 "Schedule posé, enfant supprimé (le Schedule le recréera)"
      ;;
    2)
      [[ "$(m29_git_lire "$_E20_GITOPS" "$_E20_VALEURS" 2>/dev/null | yq -r '.chaosDaemon.runtime // ""')" == containerd ]] || return 10
      _e20_netem diagnostic-latence 30m "$_M29_CHAOS_NS" | wb_kubectl apply -f - >/dev/null || return 1
      m29_poser E20 objets "$_M29_CHAOS_NS networkchaos diagnostic-latence"
      m29_attendre 120 _e20_un_netem || return 10
      tmp="$(m29_etat E20)/values.yaml"
      m29_git_lire "$_E20_GITOPS" "$_E20_VALEURS" | S="$_E20_SOCKET_FAUX" yq '.chaosDaemon.socketPath = strenv(S)' >"$tmp" || return 1
      m29_git_debut E20 "$_E20_GITOPS"
      m29_git_fichier E20 "$_E20_VALEURS" "$tmp"
      m29_git_valider E20 "fix(chaos-mesh): socket containerd explicite pour les daemons (M29-E20)

Suite à la mise à jour de containerd, chemin repris de la doc. -- Lucas" || return $?
      m29_rafraichir chaos-mesh
      m29_attendre 480 _e20_daemon_casse || return 10
      sleep 60
      # Lucas veut arrêter son expérience : il la supprime.
      wb_kubectl -n "$_M29_CHAOS_NS" delete networkchaos diagnostic-latence --wait=false >/dev/null 2>&1 || true
      sleep 90
      # Effet attendu : l'objet reste (finaliseur) ET le netem reste.
      wb_kubectl -n "$_M29_CHAOS_NS" get networkchaos diagnostic-latence >/dev/null 2>&1 || return 10
      ;;
    3)
      _e20_netem diagnostic-reseau 48h "$_M29_CHAOS_NS" fausse-pause | wb_kubectl apply -f - >/dev/null || return 1
      m29_poser E20 objets "$_M29_CHAOS_NS networkchaos diagnostic-reseau"
      m29_attendre 120 _e20_un_netem || return 10
      ;;
  esac
  # L'effet doit être là (après un éventuel retour du Schedule).
  for ((i = 0; i < 42; i++)); do
    _e20_un_netem && break
    sleep 10
  done
  _e20_un_netem || return 10
  m29_journal E20 "variante $n posée"
}

_m29E20_defaire() {
  local ns type nom
  # 1. d'abord ce qui empêche le retrait : la configuration des daemons
  m29_git_annuler E20 || true
  m29_rafraichir chaos-mesh
  if _e20_daemon_casse; then m29_attendre 480 _e20_daemon_bon || true; fi
  # 2. puis ce qui recrée et ce qui est injecté
  while read -r ns type nom; do
    [[ -n "${nom:-}" ]] || continue
    if [[ "$type" == schedule ]]; then
      wb_kubectl -n "$ns" annotate schedule "$nom" experiment.chaos-mesh.org/pause=true --overwrite >/dev/null 2>&1 || true
      while IFS= read -r e; do
        [[ -n "$e" ]] && m29_supprimer_chaos "$ns" networkchaos "$e"
      done < <(_e20_enfants)
    fi
    m29_supprimer_chaos "$ns" "$type" "$nom"
  done < <(m29_lire E20 objets)
  # 3. vérification sur les nœuds, retrait manuel en dernier recours
  sleep 15
  if _e20_un_netem; then
    m29_nettoyer_netem_api
    m29_journal E20 "netem resté sur l'API retiré à la main"
  fi
  m29_oublier E20 objets
}

panne_E20_v1() { _e20_sain && m29_essayer E20 3 1; }
panne_E20_v2() { _e20_sain && m29_essayer E20 3 2; }
panne_E20_v3() { _e20_sain && m29_essayer E20 3 3; }

verifier_E20() { _e20_un_netem; }

annuler_E20() {
  _m29E20_defaire
  if _e20_un_netem; then
    wb_avert "un netem reste sur un pod de l'API de recette : redémarre ce pod (kubectl -n $_M29_RECETTE delete pod …)"
  fi
  m29_journal E20 "annulation"
}

resume_E20() {
  echo "La recette de MédiAgenda reste lente (au moins 300 ms de plus par appel) alors que l'expérience de chaos est censée être arrêtée."
}

symptome_E20() {
  case "$WB_VAR" in
    1) wb_symptome "Ticket INC-5620 — De : Julien Petit" \
         "La recette de MédiAgenda est lente depuis cette nuit (chaque appel prend au moins 300 ms de plus)." \
         "Lucas m'a dit qu'il avait lancé une expérience de latence et qu'il l'avait SUPPRIMÉE hier" \
         "soir, et c'est vrai, je l'ai vue disparaître. Mais ça revient. On ne peut pas tester la" \
         "version de demain dans ces conditions." ;;
    2) wb_symptome "Ticket INC-5620 — De : Lucas Martin" \
         "J'ai voulu arrêter mon expérience « diagnostic-latence » en la supprimant, mais elle reste" \
         "en suppression depuis des minutes et la recette est toujours lente. J'ai aussi corrigé le" \
         "chemin du socket de containerd des daemons ce matin, comme dans la doc, sans rapport je pense." \
         "Je n'ose plus rien toucher." ;;
    *) wb_symptome "Ticket INC-5620 — De : Lucas Martin" \
         "J'ai mis en pause mon expérience « diagnostic-reseau » dans chaos-experiences hier soir," \
         "l'annotation de pause est bien sur l'objet (kubectl describe), mais Julien dit que la" \
         "recette est toujours lente. Je ne comprends pas, la pause est censée retirer la latence." ;;
  esac
  printf '  %s\n\n' "Temps cible : 45 min. Contrôle : lab/bin/check 29 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 29 E20 3 "$@"; }
fi
