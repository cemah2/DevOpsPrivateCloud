# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et requêtes TraceQL entre apostrophes
# _m23-decouverte.sh — fonctions partagées par les vérifications des paliers 1 et 2 du module 23
# (check-E02 à check-E12) ; réutilisables par les paliers 3, 4 et le mini-projet. Sourcé, jamais lancé seul.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Lecture seule : « kube » (compte wb-checks, sans les Secrets ; ClusterRole wb-checks-observabilite
# pour opentelemetry.io et monitoring.coreos.com), API de Grafana avec le jeton Viewer des checks (proxy de
# la source Tempo en GET), API de Kubernetes en GET vers Tempo (services/proxy) en repli, Prometheus /
# Thanos Query (GET), Loki (GET), GitLab (jeton read_api), RGW en liste (~/.config/workbook/s3-tempo.env).
# Préfixe _m23d_ : pas de collision avec les autres paliers quand un check en charge plusieurs.
#
# Variables de lab/lab.env (facultatives) :
#   WB_M23_TEMPO_UID    UID de la source Grafana Tempo (défaut : tempo)
#   WB_M23_S3_TEMPO     fichier d'identifiants RGW de Tempo (défaut : ~/.config/workbook/s3-tempo.env)
#   WB_RGW_ENDPOINT     point d'accès du RGW (défaut : https://rgw.par1.medisphere.internal)

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m23d_ns=traces
  _m23d_tempo_uid="${WB_M23_TEMPO_UID:-tempo}"
  _m23d_s3_tempo="${WB_M23_S3_TEMPO:-$HOME/.config/workbook/s3-tempo.env}"
  _m23d_rgw="${WB_RGW_ENDPOINT:-https://rgw.par1.medisphere.internal}"
  _m23d_lb=10.10.41.63
  # Image des Collectors : distribution contrib, par Harbor, version 0.16x épinglée.
  _m23d_re_image='^registry\.par1\.medisphere\.internal/.+/opentelemetry-collector-contrib:0\.16[0-9]\.[0-9]+$'
}

# --- Kubernetes ---------------------------------------------------------------------------------

# _m23d_json ARGS… — JSON de « kube get ARGS -o json », « null » en cas d'erreur.
_m23d_json() {
  local s
  s="$(kube get "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m23d_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m23d_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m23d_app_saine NOM — Application Argo CD Synced et Healthy.
_m23d_app_saine() {
  _m23d_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _m23d_collector_pret NOM — la charge créée par l'opérateur (NOM-collector) est prête et à jour.
_m23d_collector_pret() {
  _m23d_kq '(.status.availableReplicas // 0) >= 1 and (.status.updatedReplicas // 0) == (.spec.replicas // 1)' \
    -n "$_m23d_ns" deployment "$1-collector" ||
    _m23d_kq '.status.desiredNumberScheduled > 0 and (.status.numberReady // 0) == .status.desiredNumberScheduled and (.status.updatedNumberScheduled // 0) == .status.desiredNumberScheduled' \
      -n "$_m23d_ns" daemonset "$1-collector"
}

# _m23d_cr NOM 'filtre jq' [options jq…] — le CR OpenTelemetryCollector vivant satisfait le filtre
# (appliqué à l'objet entier ; options jq possibles, ex. --arg re "…").
_m23d_cr() {
  local n="$1" f="$2"
  shift 2
  kube get -n "$_m23d_ns" opentelemetrycollectors.opentelemetry.io "$n" -o json 2>/dev/null |
    jq -e "$@" "$f" >/dev/null 2>&1
}

# _m23d_pipeline NOM — processeurs du pipeline « traces » du CR, un par ligne (vide si absent).
_m23d_processeurs() {
  kube get -n "$_m23d_ns" opentelemetrycollectors.opentelemetry.io "$1" -o json 2>/dev/null |
    jq -r '.spec.config.service.pipelines.traces.processors[]?' 2>/dev/null || true
}

# --- Tempo (par la source Grafana, sinon par le mandataire de l'API Kubernetes) ----------------------

# _m23d_tempo_get CHEMIN — GET sur l'API HTTP de Tempo (CHEMIN commence par « / »).
_m23d_tempo_get() {
  grafana_api "datasources/proxy/uid/$_m23d_tempo_uid$1" 2>/dev/null ||
    kube get --raw "/api/v1/namespaces/$_m23d_ns/services/tempo:3200/proxy$1" 2>/dev/null
}

# _m23d_traceql_nb 'TraceQL' SECONDES — nombre de traces (≤ 100) trouvées sur les SECONDES dernières
# secondes ; -1 si Tempo n'a pas répondu ou a refusé la requête (jamais confondu avec « aucune trace »).
_m23d_traceql_nb() {
  local q fin r
  q="$(jq -rn --arg v "$1" '$v | @uri')"
  fin="$(date +%s)"
  r="$(_m23d_tempo_get "/api/search?q=$q&start=$((fin - $2))&end=$fin&limit=100")" || r=""
  if jq -e 'has("traces")' >/dev/null 2>&1 <<<"$r"; then
    jq '[.traces[]?] | length' <<<"$r"
  else
    echo -1
  fi
}

# _m23d_traces SECONDES 'TraceQL' — au moins une trace (pour check_cmd).
_m23d_traces() { (($(_m23d_traceql_nb "$2" "$1") > 0)); }
# _m23d_sans_traces SECONDES 'TraceQL' — Tempo a répondu, et aucune trace.
_m23d_sans_traces() { (($(_m23d_traceql_nb "$2" "$1") == 0)); }

# --- Prometheus (Thanos Query) ---------------------------------------------------------------------

# _m23d_prom_positif 'PromQL' — au moins une série de valeur strictement positive.
_m23d_prom_positif() {
  prom_requete "$1" 2>/dev/null |
    jq -e '[.data.result[]?.value[1] | tonumber | select(. > 0)] | length > 0' >/dev/null 2>&1
}

# _m23d_prom_nul 'PromQL' — Prometheus a RÉPONDU et aucune valeur n'est strictement positive (une
# absence de réponse n'est jamais prise pour « zéro »).
_m23d_prom_nul() {
  local r
  r="$(prom_requete "$1" 2>/dev/null)" || return 1
  jq -e '.status == "success" and ([.data.result[]?.value[1] | tonumber | select(. > 0)] | length == 0)' >/dev/null 2>&1 <<<"$r"
}

# --- GitLab (lecture) ----------------------------------------------------------------------------

_m23d_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# _m23d_fichier PROJET CHEMIN [REF=main] — contenu brut du fichier (code ≠ 0 s'il est absent).
_m23d_fichier() {
  gitlab_api "projects/$(_m23d_enc "$1")/repository/files/$(_m23d_enc "$2")/raw?ref=${3:-main}"
}

# _m23d_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (casse ignorée).
_m23d_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m23d_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m23d_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif, main).
_m23d_arbre() {
  gitlab_api "projects/$(_m23d_enc "$1")/repository/tree?ref=main&path=$(_m23d_enc "$2")&recursive=true&per_page=100" 2>/dev/null |
    jq -r '.[]? | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m23d_doc_nom DOSSIER MOTIF REGEX… — un fichier de plateforme/medisphere sous DOSSIER, dont le NOM
# contient MOTIF, contient chaque REGEX.
_m23d_doc_nom() {
  local d="$1" mot="$2" f
  shift 2
  f="$(_m23d_arbre plateforme/medisphere "$d" | awk -F/ -v p="$mot" 'index($NF, p) > 0' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m23d_contient plateforme/medisphere "$f" "$@"
}

# --- Grafana -----------------------------------------------------------------------------------------

# _m23d_sources_grafana — contenu de toutes les ConfigMaps de sources de Grafana (étiquette du sidecar,
# espace supervision), texte concaténé. Les sources de M21-M23 sont déclarées par code (pas de clic).
_m23d_sources_grafana() {
  kube get configmaps -n supervision -l grafana_datasource=1 -o json 2>/dev/null |
    jq -r '.items[]?.data // {} | to_entries[] | .value' 2>/dev/null || true
}

# --- Stockage objet ------------------------------------------------------------------------------------

# _m23d_s3 FICHIER_ENV ARGS… — « aws s3api » avec l'identité du fichier (AWS_ACCESS_KEY_ID…), sous-shell.
_m23d_s3() {
  local f="$1"
  shift
  [[ -r "$f" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    . "$f"
    set +a
    exec aws --endpoint-url "$_m23d_rgw" --output json "$@" </dev/null
  )
}
