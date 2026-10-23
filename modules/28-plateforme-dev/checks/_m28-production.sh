# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m28-production.sh — fonctions partagées par les vérifications du palier 3 du module 28 (check-E13 à
# check-E17), reprises par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Lecture seule : « kube » (compte wb-checks : ClusterRole agrégée wb-checks-services-m28, jamais les
# Secrets), GitLab en GET (jeton read_api), Prometheus et Loki en GET, Grafana (Viewer), catalogue du
# portail (jeton des checks). Préfixe _m28p_ : évite les collisions avec _m28d_ et _m28o_ (paliers 1-2).

# --- Kubernetes ------------------------------------------------------------------------------------------

_m28p_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _m28p_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m28p_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m28p_so ESPACE — ScaledObject medinotif (JSON) ; vide si absent.
_m28p_so() { kube -n "$1" get scaledobjects.keda.sh medinotif -o json 2>/dev/null || true; }

# _m28p_so_ok ESPACE 'filtre jq' — le ScaledObject existe et satisfait le filtre.
_m28p_so_ok() { _m28p_so "$1" | jq -e "$2" >/dev/null 2>&1; }

# Filtres réutilisés (ScaledObject sain, déclencheurs attendus).
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _M28P_SO_PRET='any(.status.conditions[]?; .type == "Ready" and .status == "True")
    and ((.metadata.annotations // {}) | (has("autoscaling.keda.sh/paused") or has("autoscaling.keda.sh/paused-replicas")) | not)'
  _M28P_SO_TRIGGERS='([.spec.triggers[].type] | (index("rabbitmq") != null and index("cron") != null and index("prometheus") != null))
    and ([.spec.triggers[] | select(.type == "cron") | .metadata.timezone] | all(. == "Europe/Paris"))'
  _M28P_SO_ROBUSTE='(.spec.fallback.failureThreshold // 0) > 0 and (.spec.fallback.replicas // 0) > 0
    and (.spec.advanced.horizontalPodAutoscalerConfig.behavior // null) != null'
}

# _m28p_pods_prio ESPACE SÉLECTEUR CLASSE — au moins un pod en cours d'exécution, et tous ceux qui tournent
# portent la classe (les pods terminés d'un Job de migration qui partagerait l'étiquette sont ignorés).
_m28p_pods_prio() {
  kube -n "$1" get pods -l "$2" --field-selector=status.phase=Running -o json 2>/dev/null |
    jq -e --arg c "$3" '(.items | length) > 0 and all(.items[]; .spec.priorityClassName == $c)' >/dev/null 2>&1
}

# _m28p_tenant NOM 'filtre jq' — le Tenant existe et satisfait le filtre.
_m28p_tenant() { _m28p_kq "$2" tenants.capsule.clastix.io "$1"; }

# --- Prometheus ------------------------------------------------------------------------------------------

# _m28p_prom_vrai 'PromQL' — au moins une série de valeur > 0.
_m28p_prom_vrai() {
  prom_requete "$1" 2>/dev/null | jq -e '[.data.result[]?.value[1] | tonumber | select(. > 0)] | length > 0' >/dev/null 2>&1
}

# _m28p_prom_repond — Prometheus (Thanos Query) répond à une requête triviale.
_m28p_prom_repond() { prom_requete 'vector(1)' 2>/dev/null | jq -e '.status == "success"' >/dev/null 2>&1; }

# _m28p_alerte_chargee 'regex de nom' — une règle d'alerte dont le nom correspond est chargée.
_m28p_alerte_chargee() {
  prom_api rules 2>/dev/null |
    jq -e --arg r "$1" '[.data.groups[].rules[] | select(.type == "alerting" and (.name | test($r)))] | length >= 1' >/dev/null 2>&1
}

# --- GitLab (documentation et code) ------------------------------------------------------------------------

_m28p_fichier_main() {
  local p="${1//\//%2F}" f
  f="$(jq -rn --arg s "$2" '$s|@uri')"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m28p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif.
_m28p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m28p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m28p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m28p_arbre() {
  local p="${1//\//%2F}" d="${2//\//%2F}" page=1 r
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100&page=$page" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _m28p_doc PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous docs/plateforme-dev de plateforme/medisphere
# (main, récursif) contient chaque motif.
_m28p_doc() {
  local pre="$1" f
  shift
  f="$(_m28p_arbre plateforme/medisphere docs/plateforme-dev | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m28p_fichier_contient plateforme/medisphere "$f" "$@"
}

# _m28p_doc_k8s PRÉFIXE REGEX… — même chose sous docs/kubernetes (post-mortems).
_m28p_doc_k8s() {
  local pre="$1" f
  shift
  f="$(_m28p_arbre plateforme/medisphere docs/kubernetes | awk -F/ -v p="$pre" 'index($NF, p) > 0' | head -n 1)" || f=""
  [[ -n "$f" ]] || return 1
  _m28p_fichier_contient plateforme/medisphere "$f" "$@"
}

# _m28p_mr_existe PROJET 'regex de titre' — au moins une MR (tout état) dont le titre correspond.
_m28p_mr_existe() {
  gitlab_api "projects/${1//\//%2F}/merge_requests?state=all&per_page=100" 2>/dev/null |
    jq -e --arg r "$2" '[.[] | select(.title | test($r; "i"))] | length >= 1' >/dev/null 2>&1
}
