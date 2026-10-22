# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et requêtes entre apostrophes
# _m23-production.sh — fonctions partagées par les vérifications du palier 3 du module 23 (check-E13 à
# check-E16), réutilisées par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Lecture seule : « kube » (compte wb-checks, sans les Secrets), API de Grafana avec le jeton Viewer des
# checks (y compris le proxy des sources Tempo et Pyroscope, en GET), Prometheus/Thanos Query (GET), GitLab
# (jeton read_api), stockage objet RGW en liste (identité dédiée, ~/.config/workbook/s3-*.env).
# Préfixe _m23p_ : évite les collisions quand check-E25 charge plusieurs checks.

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m23p_ns=traces
  _m23p_passerelle=otel-passerelle
  _m23p_agent=otel-agent
  _m23p_attr_env="${WB_M23_ATTR_ENV:-resource.deployment.environment.name}"
  _m23p_rgw="${WB_RGW_ENDPOINT:-https://rgw.par1.medisphere.internal}"
  _m23p_lb=10.10.41.63
  _m23p_nom_otlp=otlp.apps.par1.medisphere.internal
}

# --- Kubernetes (compte wb-checks) ------------------------------------------------------------

# _m23p_json ARGS… — JSON de « kube get ARGS -o json », ou « null ».
_m23p_json() {
  local s
  s="$(kube get "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m23p_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m23p_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m23p_collector_pret NOM — la charge du collector (Deployment ou DaemonSet NOM-collector) est à jour et prête.
_m23p_collector_pret() {
  _m23p_kq '(.status.availableReplicas // 0) >= 1 and (.status.updatedReplicas // 0) == (.spec.replicas // 1)' \
    -n "$_m23p_ns" deployment "$1-collector" ||
    _m23p_kq '(.status.numberReady // 0) == .status.desiredNumberScheduled and .status.desiredNumberScheduled > 0' \
      -n "$_m23p_ns" daemonset "$1-collector"
}

# _m23p_config_collector NOM 'filtre jq sur .spec.config' — le CR vivant satisfait le filtre.
_m23p_config_collector() {
  _m23p_kq ".spec.config | $2" -n "$_m23p_ns" opentelemetrycollectors.opentelemetry.io "$1"
}

# _m23p_tempo_conf — configuration rendue de Tempo (ConfigMap « tempo », clé tempo.yaml), texte.
_m23p_tempo_conf() { kube -n "$_m23p_ns" get configmap tempo -o jsonpath='{.data.tempo\.yaml}' 2>/dev/null; }

# _m23p_tempo_conf_jq 'filtre jq' — filtre booléen sur la configuration de Tempo convertie en JSON.
_m23p_tempo_conf_jq() {
  _m23p_tempo_conf | yq -o json '.' 2>/dev/null | jq -e "$1" >/dev/null 2>&1
}

# _m23p_application_saine NOM — Application Argo CD Synced et Healthy.
_m23p_application_saine() {
  _m23p_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# --- Grafana, Tempo, Pyroscope -------------------------------------------------------------------

_M23P_SETTINGS=""
_m23p_settings() {
  if [[ -z "$_M23P_SETTINGS" ]]; then
    _M23P_SETTINGS="$(grafana_api "frontend/settings" 2>/dev/null)" || _M23P_SETTINGS=""
    jq -e . >/dev/null 2>&1 <<<"$_M23P_SETTINGS" || _M23P_SETTINGS='{}'
  fi
  printf '%s\n' "$_M23P_SETTINGS"
}

# _m23p_ds TYPE [regex sur le nom] — JSON de la première source Grafana de ce type (visible du compte des checks).
_m23p_ds() {
  _m23p_settings | jq -c --arg t "$1" --arg r "${2:-.}" '[.datasources[]? | select(.type == $t and (.name | test($r; "i")))][0] // empty'
}
_m23p_ds_uid() { _m23p_ds "$@" | jq -r '.uid // empty'; }

_m23p_tempo_uid() {
  if [[ -n "${WB_M23_TEMPO_UID:-}" ]]; then printf '%s\n' "$WB_M23_TEMPO_UID"; else _m23p_ds_uid tempo; fi
}

# _m23p_traceql_nb 'TraceQL' SECONDES — nombre de traces (≤ 100) trouvées sur les SECONDES dernières secondes ;
# -1 si Tempo n'a pas pu être interrogé (source introuvable, API en erreur) : jamais confondu avec « aucune trace ».
_m23p_traceql_nb() {
  local uid q fin r
  uid="$(_m23p_tempo_uid)" || uid=""
  [[ -n "$uid" ]] || { echo -1; return 0; }
  q="$(jq -rn --arg v "$1" '$v | @uri')"
  fin="$(date +%s)"
  r="$(grafana_api "datasources/proxy/uid/$uid/api/search?q=$q&start=$((fin - $2))&end=$fin&limit=100" 2>/dev/null)" || r=""
  jq -e 'has("traces")' >/dev/null 2>&1 <<<"$r" || { echo -1; return 0; }
  jq '[.traces[]?] | length' <<<"$r"
}

# _m23p_traces SECONDES 'TraceQL' — au moins une trace (utilisable par check_cmd).
_m23p_traces() { (($(_m23p_traceql_nb "$2" "$1") > 0)); }
_m23p_sans_traces() { (($(_m23p_traceql_nb "$2" "$1") == 0)); }

# _m23p_profils SERVICE [TYPE] — Pyroscope (par le proxy de la source Grafana) a des échantillons récents (15 min).
_m23p_profils() {
  local uid q t="${2:-process_cpu:cpu:nanoseconds:cpu:nanoseconds}"
  uid="${WB_M23_PYROSCOPE_UID:-$(_m23p_ds_uid grafana-pyroscope-datasource)}"
  [[ -n "$uid" ]] || return 1
  q="$(jq -rn --arg v "$t{service_name=\"$1\"}" '$v | @uri')"
  grafana_api "datasources/proxy/uid/$uid/pyroscope/render?query=$q&from=now-15m&until=now&format=json" 2>/dev/null |
    jq -e '((.flamebearer.numTicks // 0) > 0) or (([.timeline.samples[]?] | add // 0) > 0)' >/dev/null 2>&1
}

# --- Prometheus (Thanos Query) -------------------------------------------------------------------

# _m23p_prom_nb 'PromQL' — nombre de séries du résultat (0 en cas d'erreur).
_m23p_prom_nb() { prom_requete "$1" 2>/dev/null | jq '.data.result | length' 2>/dev/null || echo 0; }
_m23p_prom_present() { (($(_m23p_prom_nb "$1") > 0)); }

# _m23p_prom_valeur_sous 'PromQL' SEUIL — toutes les valeurs du résultat sont < SEUIL (et il y a un résultat).
_m23p_prom_valeur_sous() {
  prom_requete "$1" 2>/dev/null | jq -e --argjson s "$2" '(.data.result | length) > 0 and all(.data.result[]; (.value[1] | tonumber) < $s)' >/dev/null 2>&1
}
# _m23p_prom_nul_ou_absent 'PromQL' — aucune valeur strictement positive.
_m23p_prom_nul_ou_absent() {
  local r
  r="$(prom_requete "$1" 2>/dev/null)" || return 1
  jq -e '.status == "success" and ([.data.result[]?.value[1] | tonumber | select(. > 0)] | length == 0)' >/dev/null 2>&1 <<<"$r"
}

# --- GitLab (lecture) ----------------------------------------------------------------------------

_m23p_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# _m23p_fichier PROJET CHEMIN — contenu d'un fichier de main.
_m23p_fichier() { gitlab_api "projects/$(_m23p_enc "$1")/repository/files/$(_m23p_enc "$2")/raw?ref=main"; }

# _m23p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m23p_arbre() {
  gitlab_api "projects/$(_m23p_enc "$1")/repository/tree?ref=main&path=$(_m23p_enc "$2")&recursive=true&per_page=100" 2>/dev/null |
    jq -r '.[]? | select(.type == "blob") | .path'
}

# _m23p_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (insensible à la casse).
_m23p_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m23p_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m23p_doc DOSSIER PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous DOSSIER de plateforme/medisphere contient chaque motif.
_m23p_doc() {
  local d="$1" pre="$2" f
  shift 2
  f="$(_m23p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m23p_contient plateforme/medisphere "$f" "$@"
}

# _m23p_doc_nom DOSSIER MOTIF REGEX… — un fichier dont le NOM contient MOTIF, sous DOSSIER de plateforme/medisphere,
# contient chaque motif (ex. le post-mortem « *INC-5023* »).
_m23p_doc_nom() {
  local d="$1" mot="$2" f
  shift 2
  f="$(_m23p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$mot" 'index($NF, p) > 0' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m23p_contient plateforme/medisphere "$f" "$@"
}

# _m23p_depot_contient PROJET DOSSIER REGEX — un fichier sous DOSSIER (main) contient la regex.
_m23p_depot_contient() {
  local f
  for f in $(_m23p_arbre "$1" "$2"); do
    if _m23p_fichier "$1" "$f" 2>/dev/null | grep -Eq -- "$3"; then return 0; fi
  done
  return 1
}

# --- Stockage objet (RGW de ceph-par1), lecture seule ---------------------------------------------

# _m23p_s3 FICHIER_ENV ARGS… — aws s3api avec l'identité du fichier (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
_m23p_s3() {
  local f="$1"
  shift
  [[ -r "$f" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    . "$f"
    set +a
    exec aws --endpoint-url "$_m23p_rgw" --output json "$@" </dev/null
  )
}

# _m23p_compartiment_non_vide FICHIER_ENV COMPARTIMENT — au moins un objet.
_m23p_compartiment_non_vide() {
  _m23p_s3 "$1" s3api list-objects-v2 --bucket "$2" --max-items 5 2>/dev/null | jq -e '(.Contents // []) | length > 0' >/dev/null 2>&1
}
