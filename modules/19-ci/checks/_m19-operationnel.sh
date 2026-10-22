# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m19-operationnel.sh — fonctions partagées par les checks M19-E10 à M19-E23 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m19o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - GitLab : gitlab_api (jeton read_api des checks) ; _m19o_graphql pour une REQUÊTE GraphQL (POST
#     de lecture : le catalogue CI/CD n'a pas d'équivalent REST) ; _m19o_code pour lire un code HTTP ;
#   - cluster : « kube » (wb-checks, ClusterRoles agrégées wb-checks-*, jamais les Secrets) ; droits
#     d'un compte vérifiés par SubjectAccessReview (rien n'est écrit dans etcd, comme au M14) ;
#   - Harbor : harbor_api (robot de lecture des checks, M13) ;
#   - SonarQube (E16) : jeton du compte wb-checks (droit Browse), fichier WB_M19_SONAR_TOKEN_FILE ;
#   - Jenkins (E19-E20) : compte wb-checks (lecture), fichier WB_M19_JENKINS_CHECKS_FILE
#     (JENKINS_USER, JENKINS_TOKEN).

_M19O_P_TPL="projects/plateforme%2Fci-templates"
_M19O_P_LABO="projects/formation%2Fci-labo"
_M19O_P_API="projects/mediagenda%2Fapi"
_M19O_P_CHART="projects/mediagenda%2Fchart"
_M19O_P_DEP="projects/mediagenda%2Fdeploiement"
_M19O_P_K8S="projects/plateforme%2Fk8s"
_M19O_P_DOC="projects/plateforme%2Fmedisphere"
_M19O_TRAVAIL="$HOME/m19"
_M19O_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M19O_SONAR_URL="${WB_M19_SONAR_URL:-https://sonarqube.apps.par1.medisphere.internal}"
_M19O_JENKINS_URL="${WB_M19_JENKINS_URL:-https://jenkins.apps.par1.medisphere.internal}"
# Référence d'un composant de plateforme/ci-templates, version complète épinglée (v2.x.y).
# shellcheck disable=SC2016  # « $CI_SERVER_FQDN » est le texte littéral attendu dans le fichier
_M19O_RE_COMPOSANT='^\$CI_SERVER_FQDN/plateforme/ci-templates/[a-z][a-z0-9-]*@v2\.[0-9]+\.[0-9]+$'

# _m19o_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m19o_k() { kube "$@" 2>/dev/null || true; }

# _m19o_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m19o_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m19o_uri TEXTE — encodage URL (chemins de fichiers, noms de branches).
_m19o_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m19o_api CHEMIN — gitlab_api, vide (sans erreur) si la ressource manque.
_m19o_api() { gitlab_api "$1" 2>/dev/null || true; }

# _m19o_code CHEMIN — code HTTP d'un GET sur l'API GitLab (lecture ; « 000 » si injoignable).
_m19o_code() {
  local f="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
  [[ -r "$f" ]] || { echo 000; return 0; }
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$f")") \
    "$_M19O_GITLAB/api/v4/$1" 2>/dev/null || echo 000
}

# _m19o_graphql REQUÊTE — requête GraphQL de LECTURE (jeton read_api des checks) ; JSON ou vide.
_m19o_graphql() {
  local f="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
  [[ -r "$f" ]] || return 0
  jq -n --arg q "$1" '{query: $q}' \
    | curl -sf --max-time "$WB_TIMEOUT" -H @<(printf 'Authorization: Bearer %s\n' "$(<"$f")") \
        -H 'Content-Type: application/json' --data @- "$_M19O_GITLAB/api/graphql" 2>/dev/null || true
}

# _m19o_contenu PROJET CHEMIN [RÉF=main] — contenu brut du fichier (vide si absent).
_m19o_contenu() {
  _m19o_api "$1/repository/files/$(_m19o_uri "$2")/raw?ref=$(_m19o_uri "${3:-main}")"
}

# _m19o_fichier PROJET CHEMIN [RÉF=main] — le fichier existe sur la référence.
_m19o_fichier() {
  gitlab_api "$1/repository/files/$(_m19o_uri "$2")?ref=$(_m19o_uri "${3:-main}")" >/dev/null 2>&1
}

# _m19o_includes CONTENU_YAML — liste JSON des inclusions du .gitlab-ci.yml (toujours un tableau
# d'objets : une chaîne seule devient {"local": …}). Vide si le YAML est illisible.
_m19o_includes() {
  [[ -n "$1" ]] || return 0
  yq -o=json '.include // []' <<<"$1" 2>/dev/null \
    | jq -c 'if type == "array" then . else [.] end
             | map(if type == "string" then {local: .} else . end)' 2>/dev/null || true
}

# _m19o_que_des_composants CONTENU_YAML — au moins une inclusion, et toutes sont des composants de
# plateforme/ci-templates à une version complète v2.x.y.
_m19o_que_des_composants() {
  local inc
  inc="$(_m19o_includes "$1")"
  _m19o_json "$inc" 'length >= 1 and all(has("component") and (keys - ["component", "inputs", "rules"] | length == 0)
    and (.component | test($re)))' --arg re "$_M19O_RE_COMPOSANT"
}

# _m19o_version_composant CONTENU_YAML NOM — version (vX.Y.Z) à laquelle le composant NOM est inclus.
_m19o_version_composant() {
  _m19o_includes "$1" | jq -r --arg n "$2" \
    '[.[] | select(has("component")) | .component | select(test("/ci-templates/" + $n + "@"))][0] // "" | sub(".*@"; "")' 2>/dev/null || true
}

# _m19o_mineure_ge VERSION MAJ MIN — VERSION (vX.Y.Z) ≥ vMAJ.MIN.0.
_m19o_mineure_ge() {
  local v="${1#v}" maj min
  [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || return 1
  maj="${BASH_REMATCH[1]}"; min="${BASH_REMATCH[2]}"
  ((maj > $2 || (maj == $2 && min >= $3)))
}

# _m19o_pipeline PROJET PARAMÈTRES — dernier pipeline correspondant (JSON objet, vide sinon).
#   Ex. : _m19o_pipeline "$_M19O_P_API" "ref=main"
_m19o_pipeline() {
  _m19o_api "$1/pipelines?order_by=id&sort=desc&per_page=1&$2" | jq -c '.[0] // empty' 2>/dev/null || true
}

# _m19o_pipeline_etiquette PROJET — dernier pipeline d'une étiquette vX.Y.Z (JSON objet, vide sinon).
_m19o_pipeline_etiquette() {
  _m19o_api "$1/pipelines?scope=tags&order_by=id&sort=desc&per_page=50" \
    | jq -c '[.[] | select(.ref | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty' 2>/dev/null || true
}

# _m19o_jobs PROJET ID_PIPELINE — jobs du pipeline (sans les tentatives remplacées), JSON tableau.
_m19o_jobs() { _m19o_api "$1/pipelines/$2/jobs?per_page=100"; }

# _m19o_peut UTILISATEUR VERBE RESSOURCE [ESPACE] [GROUPE_API] — « yes »/« no » (SubjectAccessReview).
_m19o_peut() {
  local u="$1" verbe="$2" res="$3" ns="${4:-}" api="${5:-}"
  jq -n --arg u "$u" --arg v "$verbe" --arg r "$res" --arg ns "$ns" --arg a "$api" '
    {apiVersion: "authorization.k8s.io/v1", kind: "SubjectAccessReview",
     spec: {user: $u, groups: ["system:serviceaccounts", "system:authenticated"],
            resourceAttributes: ({verb: $v, resource: $r, group: $a}
              + (if $ns != "" then {namespace: $ns} else {} end))}}' \
    | kube create -f - -o json 2>/dev/null \
    | jq -r 'if .status.allowed == true then "yes" else "no" end' 2>/dev/null || echo "?"
}

# _m19o_local600 FICHIER — fichier local (adm01) non vide en mode 600.
_m19o_local600() { [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]; }

# _m19o_mediane — médiane des nombres lus sur l'entrée standard (un par ligne), entière.
_m19o_mediane() {
  sort -n | awk '{v[NR]=$1} END {if (NR == 0) {print ""} else if (NR % 2) {printf "%d\n", v[(NR+1)/2]} else {printf "%d\n", (v[NR/2]+v[NR/2+1])/2}}'
}

# _m19o_jenkins CHEMIN — GET sur l'API de Jenkins avec le compte wb-checks (identifiants passés à
#   curl par un fichier de configuration lu dans un descripteur, jamais en argument). JSON ou vide.
_m19o_jenkins() {
  local f="${WB_M19_JENKINS_CHECKS_FILE:-$HOME/.config/workbook/jenkins-checks.env}" JENKINS_USER="" JENKINS_TOKEN=""
  [[ -r "$f" ]] || return 0
  # shellcheck disable=SC1090
  source "$f"
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'user = "%s:%s"\n' "$JENKINS_USER" "$JENKINS_TOKEN") \
    "$_M19O_JENKINS_URL/$1" 2>/dev/null || true
}

# _m19o_sonar CHEMIN — GET sur l'API de SonarQube avec le jeton du compte wb-checks. JSON ou vide.
_m19o_sonar() {
  local f="${WB_M19_SONAR_TOKEN_FILE:-$HOME/.config/workbook/sonar-checks.token}"
  [[ -r "$f" ]] || return 0
  curl -sf --max-time "$WB_TIMEOUT" -H @<(printf 'Authorization: Bearer %s\n' "$(<"$f")") \
    "$_M19O_SONAR_URL/api/$1" 2>/dev/null || true
}
