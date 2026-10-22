# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E20.sh — M23-E20 « Panne : les traces sont coupées en morceaux »
#
# Il faut des traces distribuées MédiAgenda → MédiDoc en dev (M23-E06 et témoin de trafic). Variantes :
#   1. commit dans mediagenda/deploiement (overlay dev) : OTEL_PROPAGATORS=baggage sur l'API : le contexte
#      W3C (traceparent) n'est plus injecté dans l'appel vers MédiDoc, qui démarre ses propres traces ;
#   2. commit dans medidoc/deploiement (overlay dev) : OTEL_TRACES_SAMPLER=traceidratio (0.2) : MédiDoc
#      ignore la décision de son parent et ne garde qu'une partie de ses spans (traces amputées) ;
#   3. commit dans plateforme/observabilite : l'agent n'utilise plus l'exportateur « loadbalancing » mais le
#      Service ClusterIP de la passerelle : les spans d'une même trace arrivent sur des réplicas différents,
#      dont l'échantillonnage en queue décide chacun pour sa part.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m23-commun.sh
source "$WB_ROOT/modules/23-traces/corrige/pannes/_m23-commun.sh"

_E20_SEL_DIST="{resource.service.name = \"mediagenda-api\"} >> {resource.service.name = \"medidoc\" && ${_M23_ATTR_ENV} = \"dev\"}"

_e20_distribuees() { (($(m23_traceql_nb "$_E20_SEL_DIST" "$(($(date +%s) - 900))") > 0)); }

# Au moins un pod de MédiAgenda et un pod de MédiDoc (dev) sur des nœuds différents.
_e20_noeuds_distincts() {
  local a d
  a="$(wb_kubectl -n "$_M23_NS_AGENDA" get pods -l app.kubernetes.io/name=mediagenda -o json 2>/dev/null | jq -c '[.items[].spec.nodeName] | unique')"
  d="$(wb_kubectl -n "$_M23_NS_DOC" get pods -l app.kubernetes.io/name=medidoc -o json 2>/dev/null | jq -c '[.items[].spec.nodeName] | unique')"
  jq -en --argjson a "${a:-[]}" --argjson d "${d:-[]}" '[$a[] as $x | $d[] | select(. != $x)] | length > 0' >/dev/null
}

_e20_env_commit() {
  # _e20_env_commit CLÉ ESPACE APP PROJET VARIABLE VALEUR [VARIABLE VALEUR] "message"
  local cle="$1" ns="$2" app="$3" projet="$4" msg="${*: -1}" dep i ops tmp
  shift 4
  local -a kv=("${@:1:$#-1}")
  read -r dep i <<<"$(m23_charge "$ns" "$app")" || true
  [[ -n "${dep:-}" ]] || return 10
  ops='[]'
  local k
  for ((k = 0; k < ${#kv[@]}; k += 2)); do
    ops="$(jq -c --argjson a "$ops" --argjson b "$(m23_patch_env "$ns" "$dep" "$i" "${kv[k]}" "${kv[k + 1]}")" -n '$a + $b')"
  done
  # Deux ajouts « env/- » successifs restent valides en JSON 6902 ; deux remplacements visent des index distincts.
  tmp="$(m23_etat E20)/tmp"
  mkdir -p "$tmp"
  m23_overlay_avec_patch "$projet" "$dep" "$ops" "$tmp/kustomization-$cle.yaml" || return 10
  m23_commit E20 "$cle" "$projet" "$msg" "$_M23_OVERLAY" "$tmp/kustomization-$cle.yaml" || return 1
  m23_ecrire E20 "$cle-charge" "$ns $dep $i"
  m23_argo_rafraichir "$ns"
  V="${kv[0]}" VAL="${kv[1]}" m23_attendre 420 m23_deploiement_a "$ns" "$dep" "$i" \
    '[.env[]? | select(.name == env.V) | .value] | index(env.VAL) != null'
}

_m23E20_une() {
  local n="$1" f tmp expr
  tmp="$(m23_etat E20)/tmp"
  mkdir -p "$tmp"
  m23_attendre 300 _e20_distribuees || {
    wb_avert "aucune trace MédiAgenda → MédiDoc (dev) depuis 15 min : M23-E06 fait ? (WB_M23_APPEL_DOC, journaux de wb-pannes/trafic-agenda)"
    return 1
  }
  case "$n" in
    1)
      _e20_env_commit v1 "$_M23_NS_AGENDA" mediagenda "$_M23_DEPOT_AGENDA" OTEL_PROPAGATORS baggage \
        "dev : propagation allégée (en-têtes sortants)" || { _e20_defaire 1; return 10; }
      m23_debut E20
      ;;
    2)
      _e20_env_commit v2 "$_M23_NS_DOC" medidoc "$_M23_DEPOT_DOC" OTEL_TRACES_SAMPLER traceidratio OTEL_TRACES_SAMPLER_ARG 0.2 \
        "dev : échantillonnage de MédiDoc réduit à 20 %" || { _e20_defaire 2; return 10; }
      m23_debut E20
      ;;
    3)
      _e20_noeuds_distincts || return 10
      f="$(m23_otel_fichier "$_M23_AGENT")" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
      NOM="$_M23_AGENT" yq -e 'select(.kind == "OpenTelemetryCollector" and .metadata.name == strenv(NOM)) | .spec.config.exporters | keys | .[] | select(test("^loadbalancing"))' "$tmp/orig.yaml" >/dev/null 2>&1 || return 10
      expr='.exporters["otlp_grpc/passerelle"] = (((.exporters | to_entries | map(select(.key | test("^loadbalancing"))) | .[0].value.protocol.otlp) // {}) + {"endpoint": "otel-passerelle-collector.traces.svc.cluster.local:4317"})
        | .exporters["otlp_grpc/passerelle"].tls = (.exporters["otlp_grpc/passerelle"].tls // {"insecure": true})
        | .service.pipelines |= with_entries(select(.key | test("^traces")) |= (.value.exporters |= ((map(select(test("^loadbalancing") | not))) + ["otlp_grpc/passerelle"])))'
      m23_otel_modifier "$_M23_AGENT" "$expr" "$tmp/orig.yaml" "$tmp/neuf.yaml" || return 1
      m23_commit E20 v3 "$_M23_DEPOT_OBS" "otel : agent, envoi simplifié vers le Service de la passerelle" \
        "$f" "$tmp/neuf.yaml" || return 1
      m23_argo_rafraichir "$_M23_TRACES"
      m23_attendre 420 m23_otel_vivant "$_M23_AGENT" '.exporters | has("otlp_grpc/passerelle")' ||
        { _e20_defaire 3; return 10; }
      m23_debut E20
      ;;
  esac
  m23_journal E20 "variante $n posée"
}

_e20_defaire() {
  local n="$1"
  if m23_commit_actif E20 "v$n"; then
    m23_retablir E20 "v$n" || true
    case "$n" in
      1) m23_argo_rafraichir "$_M23_NS_AGENDA" ;;
      2) m23_argo_rafraichir "$_M23_NS_DOC" ;;
      3) m23_argo_rafraichir "$_M23_TRACES" ;;
    esac
  else
    m23_oublier E20 "git-v$n"
  fi
  m23_oublier E20 "v$n-charge"
}

panne_E20_v1() { m23_preparer && m23_essayer E20 3 1; }
panne_E20_v2() { m23_preparer && m23_essayer E20 3 2; }
panne_E20_v3() { m23_preparer && m23_essayer E20 3 3; }

verifier_E20() {
  case "$WB_VAR" in
    [1-3]) m23_commit_actif E20 "v$WB_VAR" ;;
    *) return 1 ;;
  esac
}

annuler_E20() {
  case "${WB_VAR:-}" in
    [1-3]) _e20_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3; do _e20_defaire "$v"; done ;;
  esac
  m23_oublier E20 debut
  m23_oublier E20 tmp
  m23_journal E20 "annulation"
}

resume_E20() {
  echo "Les traces de prise de rendez-vous (dev) s'arrêtent à MédiAgenda : la partie MédiDoc est absente ou isolée."
}

symptome_E20() {
  wb_symptome "Ticket INC-5020 — De : Julien Petit" \
    "Dans Grafana, les traces de MédiAgenda (dev) qui appellent MédiDoc sont incomplètes : la span du client" \
    "HTTP vers MédiDoc est là, mais la partie MédiDoc manque, ou apparaît dans une trace séparée, sans parent." \
    "Le graphe de services ne montre plus l'arête mediagenda-api → medidoc de façon fiable." \
    "Rien n'a changé dans le code des deux applications depuis la dernière version." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 23 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 23 E20 3 "$@"; }
fi
