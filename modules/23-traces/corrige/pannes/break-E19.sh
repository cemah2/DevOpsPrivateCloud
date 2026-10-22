# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E19.sh — M23-E19 « Panne : plus aucune trace »
#
# Cible : la chaîne MédiAgenda (dev) → otel-agent → otel-passerelle → Tempo. Variantes :
#   1. commit de Lucas dans mediagenda/deploiement (overlay dev) : OTEL_EXPORTER_OTLP_ENDPOINT de l'API
#      pointe sur l'autre port OTLP de l'agent (4317 ↔ 4318) : le protocole ne correspond plus ;
#   2. commit dans plateforme/observabilite : l'exportateur de la passerelle vers Tempo vise
#      « tempo-distributor » (nom du mode microservices), qui n'existe pas ;
#   3. CiliumNetworkPolicy « traces-exposition-reduite » posée dans l'espace traces : refus (ingressDeny)
#      de tout trafic vers le port 4317 de la passerelle (les agents ne lui parlent plus) ;
#   4. commit dans plateforme/observabilite : le protocole OTLP utilisé par les applications (grpc ou http,
#      déduit du port de leur point d'accès) est retiré du récepteur de l'agent.
# Contrôle sur place : plus aucune trace de mediagenda-api (dev) dans Tempo après l'injection.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m23-commun.sh
source "$WB_ROOT/modules/23-traces/corrige/pannes/_m23-commun.sh"

_E19_CNP=traces-exposition-reduite
_E19_ANNOT=medisphere.internal/ticket
_E19_TICKET=CHG-5019

# _e19_point_agenda — « DEPLOYMENT INDEX VALEUR » du point d'accès OTLP de MédiAgenda en dev.
_e19_point_agenda() {
  local dep i val
  read -r dep i <<<"$(m23_charge "$_M23_NS_AGENDA" mediagenda)"
  [[ -n "${dep:-}" ]] || return 1
  val="$(m23_env_effective "$_M23_NS_AGENDA" "$dep" "$i" OTEL_EXPORTER_OTLP_ENDPOINT)" || return 1
  printf '%s %s %s\n' "$dep" "$i" "$val"
}

_e19_cnp() {
  cat <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E19_CNP
  namespace: $_M23_TRACES
  annotations: {$_E19_ANNOT: $_E19_TICKET}
spec:
  description: "Réduction de l'exposition OTLP (revue de sécurité)"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: $_M23_TRACES.$_M23_PASSERELLE
      app.kubernetes.io/component: opentelemetry-collector
  ingressDeny:
    - fromEntities: [all]
      toPorts:
        - ports: [{port: "4317", protocol: TCP}]
EOF
}

_m23E19_une() {
  local n="$1" dep i val neuf ops f g tmp proto expr
  tmp="$(m23_etat E19)/tmp"
  mkdir -p "$tmp"
  case "$n" in
    1)
      read -r dep i val <<<"$(_e19_point_agenda)" || true
      [[ -n "${val:-}" ]] || return 10
      case "$val" in
        *:4317*) neuf="${val/:4317/:4318}" ;;
        *:4318*) neuf="${val/:4318/:4317}" ;;
        *) return 10 ;;
      esac
      ops="$(m23_patch_env "$_M23_NS_AGENDA" "$dep" "$i" OTEL_EXPORTER_OTLP_ENDPOINT "$neuf")" || return 1
      m23_overlay_avec_patch "$_M23_DEPOT_AGENDA" "$dep" "$ops" "$tmp/kustomization.yaml" || return 10
      m23_commit E19 v1 "$_M23_DEPOT_AGENDA" "dev : harmonisation du point d'accès OTLP de l'API" \
        "$_M23_OVERLAY" "$tmp/kustomization.yaml" || return 1
      m23_ecrire E19 v1-attendu "$neuf"
      m23_argo_rafraichir "$_M23_NS_AGENDA"
      NEUF="$neuf" m23_attendre 420 m23_deploiement_a "$_M23_NS_AGENDA" "$dep" "$i" \
        '[.env[]? | select(.name == "OTEL_EXPORTER_OTLP_ENDPOINT") | .value] | index(env.NEUF) != null' ||
        { _e19_defaire 1; return 10; }
      ;;
    2)
      f="$(m23_otel_fichier "$_M23_PASSERELLE")" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
      expr='(.exporters[] | select(has("endpoint") and (.endpoint | test("tempo")) and (.endpoint | test("tempo-distributor") | not))).endpoint |= sub("tempo"; "tempo-distributor")'
      m23_otel_modifier "$_M23_PASSERELLE" "$expr" "$tmp/orig.yaml" "$tmp/neuf.yaml" || return 1
      cmp -s "$tmp/orig.yaml" "$tmp/neuf.yaml" && return 10
      m23_commit E19 v2 "$_M23_DEPOT_OBS" "otel : passerelle, exportateur Tempo aligné sur le nom du distributeur" \
        "$f" "$tmp/neuf.yaml" || return 1
      m23_argo_rafraichir "$_M23_TRACES"
      m23_attendre 420 m23_otel_vivant "$_M23_PASSERELLE" '[.exporters[]? | .endpoint? // empty | select(test("tempo-distributor"))] | length > 0' ||
        { _e19_defaire 2; return 10; }
      ;;
    3)
      _e19_cnp | wb_kubectl apply --dry-run=server -f - >/dev/null 2>&1 || return 10
      _e19_cnp | wb_kubectl apply -f - >/dev/null || return 1
      m23_ecrire E19 v3-pose 1
      m23_journal E19 "CNP $_E19_CNP posée dans $_M23_TRACES"
      ;;
    4)
      read -r dep i val <<<"$(_e19_point_agenda)" || true
      case "${val:-}" in
        *:4318*) proto=http ;;
        *) proto=grpc ;;
      esac
      f="$(m23_otel_fichier "$_M23_AGENT")" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
      g="$(NOM="$_M23_AGENT" yq "select(.kind == \"OpenTelemetryCollector\" and .metadata.name == strenv(NOM)) | .spec.config.receivers | keys | .[] | select(test(\"^otlp\"))" "$tmp/orig.yaml" | head -n 1)"
      [[ -n "$g" ]] || return 10
      PROTO="$proto" G="$g" yq -e "select(.kind == \"OpenTelemetryCollector\" and .metadata.name == \"$_M23_AGENT\") | .spec.config.receivers[strenv(G)].protocols | has(strenv(PROTO))" "$tmp/orig.yaml" >/dev/null 2>&1 || return 10
      PROTO="$proto" G="$g" m23_otel_modifier "$_M23_AGENT" 'del(.receivers[strenv(G)].protocols[strenv(PROTO)])' "$tmp/orig.yaml" "$tmp/neuf.yaml" || return 1
      m23_commit E19 v4 "$_M23_DEPOT_OBS" "otel : agent, un seul protocole OTLP (réduction de surface)" \
        "$f" "$tmp/neuf.yaml" || return 1
      m23_ecrire E19 v4-proto "$g $proto"
      m23_argo_rafraichir "$_M23_TRACES"
      G="$g" PROTO="$proto" m23_attendre 420 m23_otel_vivant "$_M23_AGENT" '(.receivers[env.G].protocols | has(env.PROTO)) | not' ||
        { _e19_defaire 4; return 10; }
      ;;
  esac
  m23_debut E19
  m23_journal E19 "variante $n posée"
  m23_plus_de_traces E19 || { _e19_defaire "$n"; return 10; }
}

_e19_defaire() {
  local n="$1" a
  case "$n" in
    1 | 2 | 4)
      if m23_commit_actif E19 "v$n"; then
        m23_retablir E19 "v$n" || true
        case "$n" in
          1) m23_argo_rafraichir "$_M23_NS_AGENDA" ;;
          *) m23_argo_rafraichir "$_M23_TRACES" ;;
        esac
      else
        m23_oublier E19 "git-v$n"
      fi
      ;;
    3)
      [[ -n "$(m23_lire E19 v3-pose)" ]] || return 0
      a="$(wb_kubectl -n "$_M23_TRACES" get ciliumnetworkpolicies.cilium.io "$_E19_CNP" -o json 2>/dev/null |
        jq -r --arg k "$_E19_ANNOT" '.metadata.annotations[$k] // empty')" || a=""
      if [[ "$a" == "$_E19_TICKET" ]]; then
        wb_kubectl -n "$_M23_TRACES" delete ciliumnetworkpolicies.cilium.io "$_E19_CNP" --ignore-not-found >/dev/null 2>&1 || true
      fi
      m23_oublier E19 v3-pose
      ;;
  esac
}

panne_E19_v1() { m23_preparer && m23_essayer E19 4 1; }
panne_E19_v2() { m23_preparer && m23_essayer E19 4 2; }
panne_E19_v3() { m23_preparer && m23_essayer E19 4 3; }
panne_E19_v4() { m23_preparer && m23_essayer E19 4 4; }

# La disparition des traces a été constatée par la fonction de panne ; on revérifie l'état injecté.
verifier_E19() {
  case "$WB_VAR" in
    1 | 2 | 4) m23_commit_actif E19 "v$WB_VAR" ;;
    3) wb_kubectl -n "$_M23_TRACES" get ciliumnetworkpolicies.cilium.io "$_E19_CNP" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  case "${WB_VAR:-}" in
    [1-4]) _e19_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e19_defaire "$v"; done ;;
  esac
  m23_oublier E19 debut
  m23_oublier E19 tmp
  m23_journal E19 "annulation"
}

resume_E19() {
  echo "Grafana ne montre plus aucune trace de MédiAgenda (dev) depuis le début de la nuit."
}

symptome_E19() {
  wb_symptome "Ticket INC-5019 — De : Julien Petit" \
    "Depuis ce matin, Grafana (Explore → Tempo) ne trouve plus AUCUNE trace de mediagenda-api en dev." \
    "L'API répond normalement, les métriques et les journaux arrivent. Hier soir tout marchait." \
    "On a une démonstration de la prise de rendez-vous à 14 h et je veux montrer les traces." \
    "Lucas a « fait un peu de ménage » dans les configurations hier. Retrouve les traces, par le code." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 23 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 23 E19 4 "$@"; }
fi
