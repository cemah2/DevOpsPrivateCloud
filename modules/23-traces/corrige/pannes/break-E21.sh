# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et PromQL entre apostrophes
# break-E21.sh — M23-E21 « Panne : le Collector perd des données »
#
# Toutes les variantes passent par un commit de Lucas dans plateforme/observabilite :
#   1. memory_limiter de la passerelle abaissé (limit_mib 32, spike_limit_mib 8) : la passerelle refuse en
#      permanence les données (« data refused due to high memory usage ») ;
#   2. file d'attente de l'exportateur Tempo de la passerelle minuscule (queue_size 5 requêtes, 1 consommateur)
#      ET Tempo ralenti (overrides.defaults.ingestion.artificial_delay 2s) : la file déborde ;
#   3. lots géants à la passerelle (batch : send_batch_size 20000, timeout 30s) ET rafale de Tempo réduite
#      (overrides.defaults.ingestion.burst_size_bytes 60000) : chaque lot dépasse la rafale permise et Tempo
#      le refuse (RATE_LIMITED) jusqu'à abandon.
# Contrôle sur place : compteurs de refus, d'échec de mise en file ou d'envoi du Collector, ou rejets de Tempo.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m23-commun.sh
source "$WB_ROOT/modules/23-traces/corrige/pannes/_m23-commun.sh"

_E21_Q_REFUS='sum(increase({__name__=~"otelcol_receiver_refused_spans(_total)?|otelcol_processor_memory_limiter_refused_spans(_total)?"}[3m]))'
_E21_Q_FILE='sum(increase({__name__=~"otelcol_exporter_enqueue_failed_spans(_total)?"}[3m]))'
_E21_Q_ENVOI='sum(increase({__name__=~"otelcol_exporter_send_failed_spans(_total)?|otelcol_exporter_enqueue_failed_spans(_total)?"}[5m])) or sum(increase(tempo_discarded_spans_total[5m]))'

_e21_constat() {
  case "$1" in
    1) m23_prom_positif "$_E21_Q_REFUS" ;;
    2) m23_prom_positif "$_E21_Q_FILE" ;;
    3) m23_prom_positif "$_E21_Q_ENVOI" ;;
  esac
}

_m23E21_une() {
  local n="$1" f fv tmp expr cond
  tmp="$(m23_etat E21)/tmp"
  mkdir -p "$tmp"
  f="$(m23_otel_fichier "$_M23_PASSERELLE")" || return 10
  m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
  case "$n" in
    1)
      NOM="$_M23_PASSERELLE" yq -e 'select(.kind == "OpenTelemetryCollector" and .metadata.name == strenv(NOM)) | .spec.config.processors | keys | .[] | select(test("^memory_limiter"))' "$tmp/orig.yaml" >/dev/null 2>&1 || return 10
      expr='(.processors[] | select(has("check_interval") or has("limit_mib") or has("limit_percentage"))) |= {"check_interval": "1s", "limit_mib": 32, "spike_limit_mib": 8}'
      m23_otel_modifier "$_M23_PASSERELLE" "$expr" "$tmp/orig.yaml" "$tmp/neuf.yaml" || return 1
      m23_commit E21 v1 "$_M23_DEPOT_OBS" "otel : passerelle, limite mémoire resserrée (économies)" "$f" "$tmp/neuf.yaml" || return 1
      cond='[.processors[]? | select(.limit_mib? == 32)] | length > 0'
      ;;
    2 | 3)
      fv="$(m23_tempo_values)" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$fv" >"$tmp/tempo-orig.yaml" || return 1
      if [[ "$n" == 2 ]]; then
        expr='(.exporters[] | select(has("endpoint") and (.endpoint | test("tempo")))) |= (.sending_queue = {"enabled": true, "sizer": "requests", "queue_size": 5, "num_consumers": 1})'
        yq '.tempo.overrides.defaults.ingestion.artificial_delay = "2s"' "$tmp/tempo-orig.yaml" >"$tmp/tempo-neuf.yaml" || return 1
        cond='[.exporters[]? | select(.sending_queue.queue_size? == 5)] | length > 0'
      else
        NOM="$_M23_PASSERELLE" yq -e 'select(.kind == "OpenTelemetryCollector" and .metadata.name == strenv(NOM)) | .spec.config.processors | keys | .[] | select(test("^batch"))' "$tmp/orig.yaml" >/dev/null 2>&1 || return 10
        expr='.processors |= with_entries(select(.key | test("^batch")) |= (.value = {"send_batch_size": 20000, "send_batch_max_size": 0, "timeout": "30s"}))'
        yq '.tempo.overrides.defaults.ingestion.burst_size_bytes = 60000' "$tmp/tempo-orig.yaml" >"$tmp/tempo-neuf.yaml" || return 1
        cond='[.processors | to_entries[] | select(.key | test("^batch")) | .value.send_batch_size] | index(20000) != null'
      fi
      m23_otel_modifier "$_M23_PASSERELLE" "$expr" "$tmp/orig.yaml" "$tmp/neuf.yaml" || return 1
      cmp -s "$tmp/orig.yaml" "$tmp/neuf.yaml" && return 10
      m23_commit E21 "v$n" "$_M23_DEPOT_OBS" "observabilité : réglages de débit de la passerelle et de Tempo" \
        "$f" "$tmp/neuf.yaml" "$fv" "$tmp/tempo-neuf.yaml" || return 1
      ;;
  esac
  m23_argo_rafraichir "$_M23_TRACES"
  m23_attendre 420 m23_otel_vivant "$_M23_PASSERELLE" "$cond" || { _e21_defaire "$n"; return 10; }
  m23_debut E21
  m23_journal E21 "variante $n posée"
  m23_attendre 420 _e21_constat "$n" || { _e21_defaire "$n"; return 10; }
}

_e21_defaire() {
  local n="$1"
  if m23_commit_actif E21 "v$n"; then
    m23_retablir E21 "v$n" || true
    m23_argo_rafraichir "$_M23_TRACES"
  else
    m23_oublier E21 "git-v$n"
  fi
}

panne_E21_v1() { m23_preparer && m23_essayer E21 3 1; }
panne_E21_v2() { m23_preparer && m23_essayer E21 3 2; }
panne_E21_v3() { m23_preparer && m23_essayer E21 3 3; }

verifier_E21() {
  case "$WB_VAR" in
    [1-3]) m23_commit_actif E21 "v$WB_VAR" ;;
    *) return 1 ;;
  esac
}

annuler_E21() {
  case "${WB_VAR:-}" in
    [1-3]) _e21_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3; do _e21_defaire "$v"; done ;;
  esac
  m23_oublier E21 debut
  m23_oublier E21 tmp
  m23_journal E21 "annulation"
}

resume_E21() {
  echo "Des traces arrivent dans Tempo, mais il en manque beaucoup : le Collector perd des données."
}

symptome_E21() {
  wb_symptome "Ticket INC-5021 — De : Karim Benali" \
    "Le tableau « Pipeline de traces » montre un trou : depuis ce matin, une grande partie des spans" \
    "reçues par les Collectors n'arrive jamais dans Tempo. Il reste des traces, mais beaucoup moins, et" \
    "des traces d'erreurs que Julien a provoquées exprès sont introuvables." \
    "Lucas a appliqué hier des « réglages de débit » trouvés sur un forum. Trouve où les données se perdent," \
    "corrige par le code et dis-moi quelle métrique aurait dû nous alerter." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 23 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 23 E21 3 "$@"; }
fi
