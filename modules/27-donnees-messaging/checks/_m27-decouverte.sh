# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m27-decouverte.sh — fonctions partagées par les checks M27-E02 à M27-E05 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m27d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (PLAN §4.13) :
#   - cluster : « kube » (compte wb-checks : ClusterRoles agrégées, dont wb-checks-services créée
#     en M27-E02 ; jamais les Secrets) ; Applications Argo CD par kube ;
#   - RabbitMQ : rabbitmq_api (utilisateur wb-checks, étiquette monitoring : métadonnées seulement) ;
#   - Prometheus : prom_requete (Thanos Query, M21) ;
#   - GitLab : gitlab_api (jeton read_api des checks).

_M27D_ENV_RECETTE="${WB_M27_ENV_RECETTE:-recette}"
_M27D_ENV_PROD="${WB_M27_ENV_PROD:-prod}"
_M27D_DOC="${WB_M27_DOC_DONNEES:-docs/donnees}"
# Mineure(s) de RabbitMQ acceptée(s) : 4.3 (E03) ou 4.4 si la montée de M27-E15 a été faite.
# WB_M27_VERSION_RABBITMQ fixe une seule mineure (ex. « 4.4 ») ; sans elle, les deux sont admises.
_M27D_VERSION_RMQ="${WB_M27_VERSION_RABBITMQ:-4.3 ou 4.4}"
if [[ -n "${WB_M27_VERSION_RABBITMQ:-}" ]]; then
  _M27D_RMQ_RE="${WB_M27_VERSION_RABBITMQ//./\\.}"
else
  _M27D_RMQ_RE='4\.[34]'
fi
_M27D_P_DOC="projects/plateforme%2Fmedisphere"
_M27D_P_DONNEES="projects/$(jq -rn --arg v "${WB_M27_PROJET_DONNEES:-plateforme/donnees}" '$v | @uri')"
_M27D_P_API="projects/$(jq -rn --arg v "${WB_M27_PROJET_API:-mediagenda/api}" '$v | @uri')"
_M27D_P_MNDEP="projects/$(jq -rn --arg v "${WB_M27_PROJET_MEDINOTIF_DEPLOIEMENT:-medinotif/deploiement}" '$v | @uri')"
_M27D_P_MGDEP="projects/mediagenda%2Fdeploiement"

# _m27d_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m27d_k() { kube "$@" 2>/dev/null || true; }

# _m27d_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m27d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m27d_app NOM — Application Argo CD (JSON), vide si absente ou illisible.
_m27d_app() { _m27d_k get applications.argoproj.io -n argocd "$1" -o json; }

# _M27D_APP_SAINE — filtre jq : Application synchronisée et saine.
# shellcheck disable=SC2016
_M27D_APP_SAINE='.status.sync.status == "Synced" and .status.health.status == "Healthy"'

# _m27d_app_source APP_JSON MOTIF_DEPOT [CHEMIN] — une des sources de l'Application vise ce dépôt (et ce chemin).
_m27d_app_source() {
  _m27d_json "$1" 'any((.spec.sources // [.spec.source])[]; (.repoURL | test($d)) and (($c == "") or (.path == $c)))' \
    --arg d "$2" --arg c "${3:-}"
}

# _m27d_rmq CHEMIN — API de gestion de RabbitMQ (JSON), vide si erreur.
_m27d_rmq() { rabbitmq_api "$1" 2>/dev/null || true; }

# _m27d_rmq_lisible — l'API de gestion répond au compte des checks.
_m27d_rmq_lisible() { [[ -n "$(_m27d_rmq overview)" ]]; }

# _m27d_prom 'PromQL' — première valeur du résultat (0 si rien ou erreur).
_m27d_prom() {
  local r
  r="$(prom_requete "$1" 2>/dev/null || true)"
  jq -r '[.data.result[]?.value[1] | tonumber] | add // 0' <<<"${r:-{\}}" 2>/dev/null || echo 0
}

# _m27d_positif NOMBRE — vrai si NOMBRE > 0 (accepte les décimaux renvoyés par Prometheus).
_m27d_positif() { awk -v n="${1:-0}" 'BEGIN { exit !(n > 0) }'; }

# _m27d_fichier_main PROJET CHEMIN [BRANCHE] — le fichier existe sur la branche (main par défaut).
_m27d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}

# _m27d_contenu_main PROJET CHEMIN [BRANCHE] — contenu brut du fichier (vide si absent).
_m27d_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m27d_doc_contient CHEMIN REGEX — le document existe sur main de plateforme/medisphere et contient le motif.
_m27d_doc_contient() {
  local c
  c="$(_m27d_contenu_main "$_M27D_P_DOC" "$1")"
  [[ -n "$c" ]] && grep -Eqi -- "$2" <<<"$c"
}

# _m27d_pods_prets NS SÉLECTEUR — nombre de pods Running et prêts.
_m27d_pods_prets() {
  _m27d_k get pods -n "$1" -l "$2" -o json |
    jq -r '[.items[] | select(.status.phase == "Running" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

# _m27d_noeuds_distincts NS SÉLECTEUR — nombre de nœuds distincts qui portent ces pods.
_m27d_noeuds_distincts() {
  _m27d_k get pods -n "$1" -l "$2" -o json |
    jq -r '[.items[].spec.nodeName // empty] | unique | length' 2>/dev/null || echo 0
}
