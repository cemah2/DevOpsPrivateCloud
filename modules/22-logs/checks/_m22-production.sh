# shellcheck shell=bash
# shellcheck disable=SC2016  # programmes awk et filtres jq entre apostrophes
# _m22-production.sh — fonctions partagées par les vérifications du palier 3 du module 22 (check-E13 à
# check-E16) et reprises par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Lecture seule : GET sur Loki (par le Service 10.10.41.62, depuis MGMT), « kube » (compte wb-checks,
# jamais les Secrets), GitLab en GET (jeton read_api), Grafana en GET (compte Viewer), S3 en lecture
# (get-bucket-versioning, get-bucket-lifecycle-configuration) avec les identifiants de s3-loki.env.
# Préfixe _m22p_ : évite les collisions quand le mini-projet charge plusieurs checks.
#
# Variables de lab/lab.env : WB_LOKI_URL, WB_M22_S3_LOKI_ENV, WB_GITLAB_*, WB_GRAFANA_*, WB_TIMEOUT.

_m22p_loki_url="${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"
_m22p_s3_env="${WB_M22_S3_LOKI_ENV:-$HOME/.config/workbook/s3-loki.env}"
_m22p_rgw="${WB_M22_RGW_URL:-https://rgw.par1.medisphere.internal}"
_m22p_compartiment=loki-k8s-par1
# Liste fermée des étiquettes (M22-E03) et étiquettes dérivées tolérées si la décision est écrite (E14).
_m22p_etiquettes_ok='^(cluster|namespace|app|container|node|job|host|role|site|service_name|__stream_shard__)$'

# --- Loki -----------------------------------------------------------------------------------------

# _m22p_loki CHEMIN [LOCATAIRE] — GET depuis la racine de Loki (ex. /config), corps sur stdout.
_m22p_loki() {
  curl -sf --max-time 20 ${2:+-H "X-Scope-OrgID: $2"} "$_m22p_loki_url$1"
}
_m22p_pret() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" "$_m22p_loki_url/ready" 2>/dev/null)" == 200 ]]; }
# _m22p_code CHEMIN [LOCATAIRE] — code HTTP d'un GET.
_m22p_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 20 ${2:+-H "X-Scope-OrgID: $2"} "$_m22p_loki_url$1" 2>/dev/null || true
}

# _m22p_yaml CHEMIN.DE.CLÉS — valeur scalaire d'un document YAML en blocs lu sur stdin (cartes
# seulement, indentation libre). Suffit pour /config, /config/tenant/v1/limits et le ConfigMap loki-runtime.
_m22p_yaml() {
  awk -v chemin="$1" '
    BEGIN { n = split(chemin, p, "."); niv = 1; ind[0] = -1 }
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*- / { next }
    {
      match($0, /^ */); i = RLENGTH; l = substr($0, i + 1)
      while (niv > 1 && i <= ind[niv - 1]) niv--
      if (l !~ /:/) next
      c = l; sub(/:.*/, "", c); gsub(/^["\047]|["\047]$/, "", c)
      if (c == p[niv]) {
        if (niv == n) {
          v = l; sub(/^[^:]+:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
          gsub(/^["\047]|["\047]$/, "", v); print v; exit
        }
        ind[niv] = i; niv++
      }
    }'
}

# _m22p_heures DURÉE — durée Loki/Prometheus (« 1y », « 30d1h », « 2w », « 336h », « 2h0m0s », « 0s »)
# en heures (entier, arrondi inférieur). Vide → -1.
_m22p_heures() {
  awk -v d="$1" 'BEGIN {
    if (d == "") { print -1; exit }
    t = 0
    while (match(d, /^[0-9.]+(ms|y|w|d|h|m|s)/)) {
      tok = substr(d, 1, RLENGTH); d = substr(d, RLENGTH + 1)
      match(tok, /[a-z]+$/); u = substr(tok, RSTART); v = substr(tok, 1, RSTART - 1) + 0
      if (u == "y") t += v * 8760; else if (u == "w") t += v * 168; else if (u == "d") t += v * 24
      else if (u == "h") t += v; else if (u == "m") t += v / 60; else if (u == "s") t += v / 3600
      else if (u == "ms") t += v / 3600000
    }
    printf "%d\n", t }'
}

# _m22p_secondes DURÉE — même chose en secondes (entier).
_m22p_secondes() {
  awk -v d="$1" 'BEGIN {
    if (d == "") { print -1; exit }
    t = 0
    while (match(d, /^[0-9.]+(ms|y|w|d|h|m|s)/)) {
      tok = substr(d, 1, RLENGTH); d = substr(d, RLENGTH + 1)
      match(tok, /[a-z]+$/); u = substr(tok, RSTART); v = substr(tok, 1, RSTART - 1) + 0
      if (u == "y") t += v * 31536000; else if (u == "w") t += v * 604800; else if (u == "d") t += v * 86400
      else if (u == "h") t += v * 3600; else if (u == "m") t += v * 60; else if (u == "s") t += v
      else if (u == "ms") t += v / 1000
    }
    printf "%d\n", t }'
}

# _m22p_limite LOCATAIRE CLÉ — limite effective publiée par /config/tenant/v1/limits.
_m22p_limite() { _m22p_loki /config/tenant/v1/limits "$1" 2>/dev/null | _m22p_yaml "$2"; }
# _m22p_config SECTION.CLÉ — valeur de /config.
_m22p_config() { _m22p_loki /config 2>/dev/null | _m22p_yaml "$1"; }

# _m22p_metrique 'regex de série' — somme des valeurs des séries de /metrics de Loki qui correspondent.
_m22p_metrique() {
  _m22p_loki /metrics 2>/dev/null | awk -v re="$1" '$0 !~ /^#/ && $0 ~ re { s += $NF; t = 1 } END { if (t) printf "%.0f\n", s; else print "absent" }'
}

# _m22p_runtime — contenu du fichier de surcharges (ConfigMap journaux/loki-runtime), vide si illisible.
_m22p_runtime() { kube -n journaux get configmap loki-runtime -o jsonpath='{.data.runtime-config\.yaml}' 2>/dev/null || true; }

# _m22p_surcharge LOCATAIRE CLÉ — valeur de la surcharge du locataire, sinon valeur globale de /config.
_m22p_surcharge() {
  local v
  v="$(_m22p_runtime | _m22p_yaml "overrides.$1.$2")"
  [[ -n "$v" ]] || v="$(_m22p_config "limits_config.$2")"
  printf '%s\n' "$v"
}

# _m22p_requete LOCATAIRE 'LogQL' [DEPUIS=1h] [PAS] — query_range ; JSON de la réponse, plus « http ».
_m22p_requete() {
  local r code
  r="$(curl -s --max-time 60 -G -w '\n%{http_code}' -H "X-Scope-OrgID: $1" --data-urlencode "query=$2" \
    --data-urlencode "since=${3:-1h}" ${4:+--data-urlencode "step=$4"} --data-urlencode "limit=1000" \
    "$_m22p_loki_url/loki/api/v1/query_range" 2>/dev/null)" || true
  code="${r##*$'\n'}"
  r="${r%$'\n'*}"
  jq -c --arg c "$code" '. + {http: ($c | tonumber? // 0)}' <<<"$r" 2>/dev/null || jq -nc --arg c "$code" '{http: ($c | tonumber? // 0)}'
}

# _m22p_nb_lignes LOCATAIRE 'LogQL' [DEPUIS] — nombre de lignes renvoyées par une requête de journaux.
_m22p_nb_lignes() { _m22p_requete "$@" | jq '[.data.result[]?.values[]?] | length' 2>/dev/null || echo 0; }

# _m22p_etiquettes LOCATAIRE [DEPUIS=1h] — étiquettes indexées vues sur la période, une par ligne.
_m22p_etiquettes() {
  curl -sf --max-time 20 -G -H "X-Scope-OrgID: $1" --data-urlencode "since=${2:-1h}" \
    "$_m22p_loki_url/loki/api/v1/labels" 2>/dev/null | jq -r '.data[]?' 2>/dev/null
}

# _m22p_etiquettes_fermees LOCATAIRE — aucune étiquette hors de la liste fermée (et au moins une).
_m22p_etiquettes_fermees() {
  local e n=0
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    n=$((n + 1))
    [[ "$e" =~ $_m22p_etiquettes_ok ]] || return 1
  done < <(_m22p_etiquettes "$1")
  ((n > 0))
}

# --- GitLab (documentation et code) -----------------------------------------------------------------

_m22p_fichier_main() {
  local p="${1//\//%2F}" f
  f="$(jq -rn --arg s "$2" '$s|@uri')"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m22p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif.
_m22p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m22p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m22p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m22p_arbre() {
  local p="${1//\//%2F}" d="${2//\//%2F}" page=1 r
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100&page=$page" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _m22p_doc DOSSIER PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous DOSSIER de plateforme/medisphere (main,
# récursif) contient chaque motif.
_m22p_doc() {
  local d="$1" pre="$2" f
  shift 2
  f="$(_m22p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m22p_fichier_contient plateforme/medisphere "$f" "$@"
}

# --- Stockage objet (lecture) -----------------------------------------------------------------------

# _m22p_s3 ARGS… — aws s3api avec les identifiants de s3-loki.env (sous-shell : rien n'est exporté ailleurs).
_m22p_s3() {
  (
    [[ -r "$_m22p_s3_env" ]] || exit 1
    set -a
    # shellcheck disable=SC1090
    . "$_m22p_s3_env"
    set +a
    aws s3api "$@" --endpoint-url "$_m22p_rgw" --output json
  ) 2>/dev/null
}

# --- Grafana ---------------------------------------------------------------------------------------

# _m22p_sources_visibles — noms des sources de données que le compte Viewer des checks peut interroger.
_m22p_sources_visibles() { grafana_api frontend/settings 2>/dev/null | jq -r '.datasources // {} | keys[]' 2>/dev/null; }
