# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E25.sh — M23-E25 « Mini-projet : l'observabilité de MédiSphère v1 » (étiquette traces-v1).
# Contrôle global depuis adm01, lecture seule : rejoue les checks clés du module (ceux des paliers 1 et 2 s'ils
# sont présents, puis E13, E14, E16) et ajoute les contrôles de livraison. 3 à 6 minutes.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E25 — L'observabilité de MédiSphère v1 : contrôle global"
require_cmd kubectl jq yq curl openssl

# --- 1. Trois signaux pour chaque environnement ---------------------------------------------------
title "1/6 Traces dans chaque environnement"
for _m23_e25_c in "mediagenda-api dev 1800" "mediagenda-api recette 1800" "mediagenda-api prod 86400" \
  "medidoc dev 1800" "medidoc recette 1800"; do
  read -r _m23_e25_s _m23_e25_e _m23_e25_d <<<"$_m23_e25_c"
  check_cmd "traces de $_m23_e25_s en $_m23_e25_e (fenêtre $((_m23_e25_d / 60)) min)" \
    _m23p_traces "$_m23_e25_d" "{resource.service.name = \"$_m23_e25_s\" && $_m23p_attr_env = \"$_m23_e25_e\"}"
done
check_cmd "traces distribuées mediagenda-api → medidoc en recette (24 h)" \
  _m23p_traces 86400 "{resource.service.name = \"mediagenda-api\"} >> {resource.service.name = \"medidoc\" && $_m23p_attr_env = \"recette\"}"
for _m23_e25_ns in mediagenda-recette mediagenda-prod medidoc-recette; do
  check_cmd "$_m23_e25_ns : composant de télémétrie appliqué (OTEL_SERVICE_NAME et OTEL_RESOURCE_ATTRIBUTES dans les pods)" \
    _m23p_kq '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] | test("^(mediagenda|medidoc)$"))
              | .spec.containers[0] | [.env[]?.name] | (index("OTEL_SERVICE_NAME") != null and index("OTEL_RESOURCE_ATTRIBUTES") != null)] | length > 0 and all' \
    -n "$_m23_e25_ns" pods
done

# --- 2. Données sensibles et bruit ----------------------------------------------------------------
title "2/6 Données sensibles et bruit"
check_cmd "aucune span de sonde (/sante, /pret, /healthz, /readyz, /metrics) sur 1 h" \
  _m23p_sans_traces 3600 '{span.http.route =~ "/(sante|pret|healthz|readyz|metrics)" || span.url.path =~ "/(sante|pret|healthz|readyz|metrics)"}'
check_cmd "aucun attribut d'identité patient ni d'en-tête d'authentification sur 1 h" \
  _m23p_sans_traces 3600 '{span.patient != nil || span.enduser.id != nil || span.http.request.header.authorization != nil}'
check_cmd "passerelle : échantillonnage en queue (tail_sampling) dans le pipeline de traces" \
  _m23p_config_collector "$_m23p_passerelle" 'any(.service.pipelines | to_entries[] | select(.key | test("^traces")); any(.value.processors[]; test("^tail_sampling")))'
_m23_e25_sans_debug() {
  _m23p_config_collector "$_m23p_passerelle" '[.service.pipelines[].exporters[] | select(test("^debug"))] | length == 0' &&
    _m23p_config_collector "$_m23p_agent" '[.service.pipelines[].exporters[] | select(test("^debug"))] | length == 0'
}
check_cmd "collectors : aucun exportateur debug en service" _m23_e25_sans_debug

# --- 3. Rejeu des checks clés -------------------------------------------------------------------------
title "3/6 Rejeu des checks clés du module"
_m23_e25_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m23_e25_x in E02 E03 E08 E09 E10; do
  if [[ -f "$_m23_e25_dir/check-$_m23_e25_x.sh" ]]; then
    # shellcheck disable=SC1090
    source "$_m23_e25_dir/check-$_m23_e25_x.sh"
  fi
done
# shellcheck source=check-E13.sh
source "$_m23_e25_dir/check-E13.sh"
# shellcheck source=check-E14.sh
source "$_m23_e25_dir/check-E14.sh"
# shellcheck source=check-E16.sh
source "$_m23_e25_dir/check-E16.sh"

# --- 4. Tableaux et SLO ---------------------------------------------------------------------------
title "4/6 Tableaux reliés aux SLO"
_m23_e25_tableau() {
  grafana_api "dashboards/uid/m23-slo-traces" 2>/dev/null | jq -e '(.dashboard | tostring) as $d
    | ($d | test("slo|pyrra"; "i")) and ($d | test("exemplar"; "i")) and ($d | test("mediagenda"))' >/dev/null 2>&1
}
check_cmd "tableau « MédiAgenda — SLO, traces et profils » (UID m23-slo-traces) : SLO, exemplars, lien vers les traces" _m23_e25_tableau
check_cmd "tableau versionné dans plateforme/observabilite/tableaux/" \
  _m23p_depot_contient plateforme/observabilite tableaux '"uid": *"m23-slo-traces"'

# --- 5. Essais retirés ----------------------------------------------------------------------------
title "5/6 Essais retirés"
_m23_e25_pas_ns() { kube get namespace default >/dev/null 2>&1 && ! kube get namespace "$1" >/dev/null 2>&1; }
check_cmd "espace jaeger-essai absent" _m23_e25_pas_ns jaeger-essai
check_cmd "aucune ressource Instrumentation « python-essai » (auto-instrumentation d'essai retirée)" \
  _m23p_kq '[.items[] | select(.metadata.name == "python-essai")] | length == 0' instrumentations.opentelemetry.io -A
check_cmd "aucun pod annoté pour l'injection automatique hors wb-essais" \
  _m23p_kq '[.items[] | select(.metadata.namespace != "wb-essais")
            | select(.metadata.annotations // {} | keys | any(test("^instrumentation\\.opentelemetry\\.io/inject-")))] | length == 0' pods -A
check_cmd "aucune panne M23 encore marquée active (lab/bin/break)" _m23x_aucune_panne_active

# --- 6. Documentation et livraison -----------------------------------------------------------------
title "6/6 Documentation et livraison"
check_cmd "ADR-0230 publié (OpenTelemetry, Tempo, Pyroscope, Jaeger écarté)" \
  _m23p_doc docs/observabilite/traces ADR-0230 'Tempo' 'Pyroscope' 'Jaeger' '[ée]chantillonnage'
check_cmd "conventions-telemetrie.md publié (attributs, noms de services, données interdites)" \
  _m23p_doc docs/observabilite/traces conventions-telemetrie 'service\.name' 'deployment\.environment' 'interdit'
check_cmd "conformite.md : requêtes TraceQL de contrôle des données sensibles, résultat daté" \
  _m23p_doc docs/observabilite/traces conformite '\{ *(span|resource)\.' '20[0-9]{2}-[01][0-9]-[0-3][0-9]'
check_cmd "demonstration.md : parcours alerte → exemplar → trace → journaux → profil, identifiant de trace à l'appui" \
  _m23p_doc docs/observabilite/traces demonstration 'exemplar' '[0-9a-f]{32}' 'profil'
check_cmd "README.md de docs/observabilite/traces : page d'accueil" _m23p_doc docs/observabilite/traces README '.'
for _m23_e25_rb in RB-230 RB-231 RB-232 RB-233; do
  check_cmd "runbook $_m23_e25_rb publié" _m23p_doc "$_m23x_runbooks" "$_m23_e25_rb" '.'
done
_m23_e25_pipeline() {
  gitlab_api "projects/plateforme%2Fobservabilite/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "plateforme/observabilite : dernier pipeline de main réussi" _m23_e25_pipeline
_m23_e25_etiquette() {
  gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/traces-v1' 2>/dev/null | jq -e '.name == "traces-v1"' >/dev/null 2>&1
}
check_cmd "étiquette traces-v1 posée sur plateforme/medisphere" _m23_e25_etiquette
