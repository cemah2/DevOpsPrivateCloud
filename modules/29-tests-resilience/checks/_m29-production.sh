# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# _m29-production.sh — fonctions partagées par les vérifications du palier 3 du module 29 (check-E13 à
# check-E17) et reprises par le palier 4 et le mini-projet. Sourcé, jamais lancé seul.
# Lecture seule : « kube » (compte wb-checks, jamais les Secrets), GitLab en GET (jeton des checks),
# Prometheus (Thanos Query) et Grafana en GET, API de gestion de RabbitMQ (compte wb-checks, étiquette
# monitoring). Préfixe _m29p_ : évite les collisions quand le mini-projet charge plusieurs checks.
#
# Variables de lab/lab.env : WB_M29_CHAOS_NS, WB_M29_PROJET_RESILIENCE, WB_M29_RECETTE_URL, WB_GITLAB_*,
# WB_PROM_URL, WB_GRAFANA_*, WB_RABBITMQ_*, WB_TIMEOUT.

_m29p_chaos_ns="${WB_M29_CHAOS_NS:-chaos-experiences}"
_m29p_resilience="${WB_M29_PROJET_RESILIENCE:-plateforme/resilience}"
_m29p_recette=mediagenda-recette

# --- GitLab (lecture) ------------------------------------------------------------------------------

_m29p_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _m29p_fichier_main PROJET CHEMIN — contenu du fichier sur main.
_m29p_fichier_main() {
  gitlab_api "projects/$(_m29p_enc "$1")/repository/files/$(_m29p_enc "$2")/raw?ref=main"
}

# _m29p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif
# (insensible à la casse).
_m29p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m29p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m29p_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main.
_m29p_arbre() {
  local p page=1 r
  p="$(_m29p_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(_m29p_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _m29p_doc DOSSIER MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous DOSSIER (récursif, main)
# dont le nom correspond à MOTIF_NOM (expression régulière étendue) contient chaque motif.
_m29p_doc() {
  local d="$1" motif="$2" f
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _m29p_fichier_contient plateforme/medisphere "$f" "$@" && return 0
  done < <(_m29p_arbre plateforme/medisphere "$d")
  return 1
}

# _m29p_yaml_json PROJET DOSSIER — tous les documents YAML des fichiers *.yaml|*.yml sous DOSSIER (main),
# en un tableau JSON. Chaque document reçoit le champ « _fichier ». Nécessite yq (mikefarah v4).
_m29p_yaml_json() {
  local f
  {
    while IFS= read -r f; do
      [[ "$f" =~ \.ya?ml$ ]] || continue
      _m29p_fichier_main "$1" "$f" 2>/dev/null |
        F="$f" yq -o=json -I=0 'select(. != null) | . + {"_fichier": strenv(F)}' 2>/dev/null
    done < <(_m29p_arbre "$1" "$2")
  } | jq -s '.' 2>/dev/null
}

# _m29p_pipeline_ok PROJET [SOURCE] — le dernier pipeline de main (ou de la source donnée, ex.
# « schedule ») a réussi.
_m29p_pipeline_ok() {
  local q="ref=main&per_page=1"
  [[ -n "${2:-}" ]] && q="source=$2&per_page=1"
  gitlab_api "projects/$(_m29p_enc "$1")/pipelines?$q" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m29p_issues PROJET ÉTIQUETTE [ÉTAT=all] — nombre d'issues portant l'étiquette.
_m29p_issues() {
  gitlab_api "projects/$(_m29p_enc "$1")/issues?labels=$(_m29p_enc "$2")&state=${3:-all}&per_page=100" 2>/dev/null |
    jq 'length' 2>/dev/null || echo 0
}

# --- Kubernetes (lecture, compte wb-checks) ---------------------------------------------------------

_m29p_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _m29p_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m29p_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m29p_lit_chaos — le compte des checks lit les objets de Chaos Mesh (ClusterRole wb-checks-services-m29, M29-E09).
_m29p_lit_chaos() { kube get networkchaos.chaos-mesh.org -A -o name >/dev/null 2>&1; }

# _m29p_types_chaos — types d'expériences (et Schedule, Workflow) de chaos-mesh.org, forme « nom.groupe ».
_m29p_types_chaos() {
  printf '%s\n' networkchaos podchaos stresschaos iochaos timechaos httpchaos dnschaos kernelchaos \
    jvmchaos blockchaos schedule workflow | sed 's/$/.chaos-mesh.org/'
}

# _m29p_chaos_tous — tous les objets de chaos du cluster (tableau JSON), types absents ignorés.
_m29p_chaos_tous() {
  local t
  {
    while IFS= read -r t; do
      kube get "$t" -A -o json 2>/dev/null | jq -c '.items[]?'
    done < <(_m29p_types_chaos)
  } | jq -s '.' 2>/dev/null
}

# _m29p_app_saine NOM — Application Argo CD Synced et Healthy.
_m29p_app_saine() {
  _m29p_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# --- Prometheus (Thanos Query) -----------------------------------------------------------------------

# _m29p_prom_val 'PromQL' — première valeur du résultat (vide si aucun).
_m29p_prom_val() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null
}

# _m29p_prom_non_vide 'PromQL' — la requête renvoie au moins une série.
_m29p_prom_non_vide() {
  prom_requete "$1" 2>/dev/null | jq -e '.status == "success" and (.data.result | length) > 0' >/dev/null 2>&1
}

# --- Expériences de chaos (analyse des manifestes, tableau JSON sur stdin) ----------------------------

# Filtres jq réutilisables : un objet de chaos « direct » (ni Schedule ni Workflow) a une durée ; aucun
# objet ne nomme un espace de prod ni messagerie ; seuls les espaces de recette et wb-essais sont visés.
# shellcheck disable=SC2034  # utilisé par les checks qui sourcent ce fichier
_m29p_jq_experiences='[.[] | select((.apiVersion // "") | startswith("chaos-mesh.org/"))]'
# shellcheck disable=SC2034
_m29p_jq_sans_duree='[.[] | select((.apiVersion // "") | startswith("chaos-mesh.org/"))
  | select(.kind != "Schedule" and .kind != "Workflow" and .kind != "StatusCheck")
  | select((.spec.duration // "") == "")] | length'
# shellcheck disable=SC2034
_m29p_jq_espaces_interdits='[.[] | .. | objects | select(has("namespaces")) | .namespaces[]?
  | select(test("-prod$|^messagerie$|^kube-system$|^argocd$|^kyverno$|^supervision$|^chaos-mesh$"))] | length'
# shellcheck disable=SC2034
_m29p_jq_espaces_hors_recette='[.[] | .. | objects | select(has("namespaces")) | .namespaces[]?
  | select(test("^(mediagenda-recette|medinotif-recette|wb-essais)$") | not)] | length'
