# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($variables jq, pas du shell)
# _m21-production.sh — fonctions partagées par les checks M21-E24 à M21-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : lab/bin/check tourne sous « set -euo pipefail » : toute commande qui peut échouer hors
# des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées (toutes facultatives) :
#   WB_PROM_URL, WB_AM_URL, WB_GRAFANA_URL (check-lib) ; WB_K8S_KUBECONFIG (kube, compte wb-checks) ;
#   WB_K8S_ADMIN_KUBECONFIG (seulement pour constater l'EXISTENCE d'un Secret, jamais son contenu) ;
#   WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE (gitlab_api) ; WB_CEPH_ADMIN (radosgw-admin, sudo -n) ;
#   WB_M21_S3_THANOS_FILE  identité RGW « thanos » (défaut ~/.config/workbook/s3-thanos.env)
#   WB_M21_RGW_URL         point d'accès du RGW (défaut https://rgw.par1.medisphere.internal)
#   WB_M21_TEMOIN_URL      Prometheus témoin de mon01 (défaut http://mon01.par1.medisphere.internal:9090)
#   WB_M21_SLO_URL         interface de Pyrra (défaut https://slo.apps.par1.medisphere.internal)
# Accès : « kube » (lecture, pas les Secrets), API de Prometheus/Thanos Query, d'Alertmanager, de
# Mailpit et de GitLab en GET, aws s3api en LECTURE (list, get), radosgw-admin « user info ».

_M21P_NS=supervision
_M21P_BUCKET=thanos-k8s-par1
_M21P_S3_ENV="${WB_M21_S3_THANOS_FILE:-$HOME/.config/workbook/s3-thanos.env}"
_M21P_RGW="${WB_M21_RGW_URL:-https://rgw.par1.medisphere.internal}"
_M21P_TEMOIN="${WB_M21_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_M21P_SLO_URL="${WB_M21_SLO_URL:-https://slo.apps.par1.medisphere.internal}"
_M21P_CEPH="${WB_CEPH_ADMIN:-ceph01}"
_M21P_DOC=plateforme/medisphere
_M21P_OBS=plateforme/observabilite

# --- API Kubernetes (compte wb-checks) ---------------------------------------------------------

# _m21p_json ARGS… — sortie JSON valide de « kube ARGS -o json », ou « null ».
_m21p_json() {
  local s
  s="$(kube "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m21p_jq JSON FILTRE [ARGS jq…] — filtre booléen jq sur un document (null → faux).
_m21p_jq() {
  local doc="$1" filtre="$2"
  shift 2
  [[ "$doc" != null ]] && jq -e "$@" "$filtre" >/dev/null 2>&1 <<<"$doc"
}

# _m21p_prometheus — CR Prometheus « kps » (JSON) ou null.
_m21p_prometheus() { _m21p_json -n "$_M21P_NS" get prometheuses.monitoring.coreos.com kps; }

# _m21p_pret TYPE NOM [MIN] — l'objet (deployment|statefulset) de l'espace supervision a au moins MIN
# réplicas prêts (défaut : tous ceux demandés, au moins 1).
_m21p_pret() {
  local o
  o="$(_m21p_json -n "$_M21P_NS" get "$1" "$2")"
  if [[ -z "${3:-}" ]]; then
    _m21p_jq "$o" '(.status.readyReplicas // 0) >= ([(.spec.replicas // 1), 1] | max)'
  else
    _m21p_jq "$o" '(.status.readyReplicas // 0) >= ($m | tonumber)' --arg m "$3"
  fi
}

# _m21p_secret_existe ESPACE NOM — le Secret existe (kubeconfig d'administration, nom seulement).
_m21p_secret_existe() {
  kubectl --kubeconfig "${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}" --request-timeout="${WB_TIMEOUT}s" \
    -n "$1" get secret "$2" -o name >/dev/null 2>&1
}

# --- Prometheus / Thanos Query (10.10.41.60) ---------------------------------------------------

# _m21p_valeur 'PromQL' — valeur du premier résultat (instantané), ou vide.
_m21p_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# _m21p_nb 'PromQL' — nombre de séries du résultat (0 si erreur).
_m21p_nb() {
  local n
  n="$(prom_requete "$1" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null)" || n=""
  printf '%s\n' "${n:-0}"
}

# _m21p_compare VALEUR OP SEUIL — comparaison numérique (awk), faux si VALEUR vide ou NaN.
_m21p_compare() {
  [[ -n "$1" && "$1" != NaN ]] && awk -v v="$1" -v s="$3" "BEGIN { exit !(v $2 s) }"
}

# _m21p_regles TYPE — réponse de /api/v1/rules?type=alert|record (JSON), ou null.
_m21p_regles() {
  local s
  s="$(prom_api "rules?type=$1" 2>/dev/null)" || s=""
  if jq -e '.status == "success"' >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m21p_alerte_chargee NOM [JSON_REGLES] — une règle d'alerte NOM est chargée par Prometheus.
_m21p_alerte_chargee() {
  local r="${2:-}"
  [[ -n "$r" ]] || r="$(_m21p_regles alert)"
  _m21p_jq "$r" 'any(.data.groups[].rules[]; .name == $n)' --arg n "$1"
}

# _m21p_groupe_charge NOM [JSON_REGLES] — un groupe de règles NOM est chargé.
_m21p_groupe_charge() {
  local r="${2:-}"
  [[ -n "$r" ]] || r="$(_m21p_regles record)"
  _m21p_jq "$r" 'any(.data.groups[]; .name == $n)' --arg n "$1"
}

# --- Stockage objet (RGW, identité « thanos », LECTURE) ----------------------------------------

_m21p_s3() {
  [[ -r "$_M21P_S3_ENV" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M21P_S3_ENV"
    set +a
    export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
    exec aws --endpoint-url "$_M21P_RGW" --output json "$@" </dev/null
  )
}

# _m21p_blocs — identifiants (ULID) des blocs du compartiment, un par ligne.
_m21p_blocs() {
  _m21p_s3 s3api list-objects-v2 --bucket "$_M21P_BUCKET" --delimiter / 2>/dev/null \
    | jq -r '.CommonPrefixes[]?.Prefix | rtrimstr("/") | select(test("^[0-9A-HJKMNP-TV-Z]{26}$"))' 2>/dev/null || true
}

# _m21p_meta ULID — meta.json d'un bloc (JSON), ou null.
_m21p_meta() {
  local s
  s="$(_m21p_s3 s3 cp "s3://$_M21P_BUCKET/$1/meta.json" - 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m21p_rgw ARGS — radosgw-admin de CONSULTATION sur le nœud _admin de ceph-par1 (sudo -n).
_m21p_rgw() { remote "$_M21P_CEPH" "sudo -n radosgw-admin $*" 2>/dev/null; }

# --- GitLab (jeton des checks, lecture) --------------------------------------------------------

# _m21p_fichier PROJET CHEMIN — contenu brut du fichier sur main, ou rien (code ≠ 0).
_m21p_fichier() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null
}

# _m21p_arbre PROJET DOSSIER — chemins des fichiers du dossier (récursif) sur main.
_m21p_arbre() {
  local p
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&path=$(jq -rn --arg v "$2" '$v | @uri')" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m21p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque REGEX
# (grep -E, insensible à la casse).
_m21p_fichier_contient() {
  local projet="$1" chemin="$2" contenu r
  shift 2
  contenu="$(_m21p_fichier "$projet" "$chemin")" || return 1
  [[ -n "$contenu" ]] || return 1
  for r in "$@"; do grep -Eqi -- "$r" <<<"$contenu" || return 1; done
}

# _m21p_doc_present PROJET DOSSIER REGEX_CHEMIN MIN_LIGNES — un fichier du DOSSIER (récursif) dont le
# chemin correspond à REGEX (grep -Ei) existe sur main et compte au moins MIN_LIGNES lignes non vides.
_m21p_doc_present() {
  local projet="$1" dossier="$2" motif="$3" min="$4" f n
  f="$(_m21p_arbre "$projet" "$dossier" | grep -Ei -- "$motif" | head -n 1)"
  [[ -n "$f" ]] || return 1
  n="$(_m21p_fichier "$projet" "$f" | grep -c '[^[:space:]]')" || n=0
  (( n >= min ))
}

# _m21p_doc_chemin PROJET DOSSIER REGEX_CHEMIN — chemin du premier fichier qui correspond, ou vide.
_m21p_doc_chemin() { _m21p_arbre "$1" "$2" | grep -Ei -- "$3" | head -n 1 || true; }

# --- Témoin de mon01 ---------------------------------------------------------------------------

_m21p_temoin() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" "$_M21P_TEMOIN/api/v1/$1" 2>/dev/null
}

_m21p_temoin_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_M21P_TEMOIN/api/v1/query" 2>/dev/null
}

# --- Alertmanager du cluster -------------------------------------------------------------------

# _m21p_am_config — configuration en vigueur (YAML), ou vide.
_m21p_am_config() { am_api status 2>/dev/null | jq -r '.config.original // empty' 2>/dev/null || true; }
