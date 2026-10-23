# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# _m29-decouverte.sh — fonctions partagées par les checks M29-E02 à M29-E05 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh). Le palier 2
# (_m29-operationnel.sh) le source aussi. Préfixe _m29d_.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - GitLab : gitlab_api (jeton read_api des checks) : fichiers, arbres, branches, paquets, pipelines ;
#   - cluster : « kube » (compte wb-checks ; objets de Chaos Mesh et k6-operator par
#     wb-checks-services-m29, M29-E09 ; jamais les Secrets) ; Prometheus du cluster : prom_requete ;
#   - outils de adm01 (kubeconform, opa, conftest, k6) lancés sur des COPIES temporaires des fichiers
#     lus dans GitLab (dossier mktemp, supprimé à la sortie) : rien n'est écrit dans le lab ;
#   - MédiAgenda de recette : GET seulement (liste des rendez-vous).
#
# Variables de lab/lab.env (défauts ci-dessous) :
#   WB_M29_RECETTE_URL         MédiAgenda de recette (https://mediagenda-recette.apps.par1.medisphere.internal)
#   WB_M29_PROJET_RESILIENCE   projet GitLab des scénarios (plateforme/resilience)

_M29D_P_K8S="plateforme/k8s"
_M29D_P_GITOPS="plateforme/gitops"
_M29D_P_POLITIQUES="plateforme/politiques"
_M29D_P_ANSIBLE="plateforme/ansible"
_M29D_P_DOC="plateforme/medisphere"
_M29D_P_RESILIENCE="${WB_M29_PROJET_RESILIENCE:-plateforme/resilience}"
_M29D_RECETTE="${WB_M29_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"

# Dossier temporaire du check, supprimé à la sortie (copies de fichiers lus dans GitLab).
_M29D_TMP="$(mktemp -d)"
trap 'rm -rf "$_M29D_TMP"' EXIT

# _m29d_k ARGS… — kubectl en lecture par le compte des checks ; sortie vide en cas d'erreur.
_m29d_k() { kube "$@" 2>/dev/null || true; }

# _m29d_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m29d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m29d_uri TEXTE — encodage pour une URL.
_m29d_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m29d_contenu PROJET CHEMIN [REF=main] — contenu brut d'un fichier (vide s'il est absent).
_m29d_contenu() {
  gitlab_api "projects/$(_m29d_uri "$1")/repository/files/$(_m29d_uri "$2")/raw?ref=$(_m29d_uri "${3:-main}")" 2>/dev/null || true
}

# _m29d_existe PROJET CHEMIN [REF=main] — le fichier existe.
_m29d_existe() {
  gitlab_api "projects/$(_m29d_uri "$1")/repository/files/$(_m29d_uri "$2")?ref=$(_m29d_uri "${3:-main}")" >/dev/null 2>&1
}

# _m29d_contient PROJET CHEMIN REGEX [REF=main] — le fichier contient une ligne qui correspond.
_m29d_contient() {
  local c
  c="$(_m29d_contenu "$1" "$2" "${4:-main}")"
  [[ -n "$c" ]] && grep -Eq -- "$3" <<<"$c"
}

# _m29d_arbre PROJET CHEMIN [REF=main] — fichiers sous CHEMIN (récursif, un par ligne).
_m29d_arbre() {
  local page=1 lot
  while :; do
    lot="$(gitlab_api "projects/$(_m29d_uri "$1")/repository/tree?ref=$(_m29d_uri "${3:-main}")&recursive=true&per_page=100&page=$page&path=$(_m29d_uri "$2")" 2>/dev/null || true)"
    [[ -n "$lot" && "$lot" != "[]" ]] || break
    jq -r '.[] | select(.type == "blob") | .path' <<<"$lot" 2>/dev/null || break
    ((page++ < 10)) || break
  done
}

# _m29d_copier PROJET CHEMIN DEST [REF=main] — recopie les fichiers sous CHEMIN dans DEST (mêmes
#   chemins relatifs à la racine du dépôt). Renvoie le nombre de fichiers copiés sur la sortie.
_m29d_copier() {
  local projet="$1" chemin="$2" dest="$3" ref="${4:-main}" f n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    mkdir -p "$dest/$(dirname "$f")"
    _m29d_contenu "$projet" "$f" "$ref" >"$dest/$f"
    n=$((n + 1))
  done < <(_m29d_arbre "$projet" "$chemin" "$ref")
  echo "$n"
}

# _m29d_dernier_pipeline PROJET [REF=main] — JSON du dernier pipeline de la branche (vide sinon).
_m29d_dernier_pipeline() {
  gitlab_api "projects/$(_m29d_uri "$1")/pipelines?ref=$(_m29d_uri "${2:-main}")&per_page=1" 2>/dev/null \
    | jq -c '.[0] // empty' 2>/dev/null || true
}

# _m29d_job_reussi PROJET REGEX [JOURS=30] — un job dont le nom correspond a réussi récemment.
_m29d_job_reussi() {
  local depuis
  depuis="$(date -u -d "-${3:-30} days" +%Y-%m-%dT%H:%M:%SZ)"
  gitlab_api "projects/$(_m29d_uri "$1")/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg re "$2" --arg d "$depuis" 'any(.[]; (.name | test($re)) and (.finished_at // "") >= $d)' >/dev/null 2>&1
}

# _m29d_version_outil COMMANDE REGEX — la version locale de l'outil correspond (adm01).
_m29d_version_outil() {
  command -v "$1" >/dev/null 2>&1 || return 1
  case "$1" in
    kubeconform) kubeconform -v 2>&1 ;;
    opa) opa version 2>&1 ;;
    conftest) conftest --version 2>&1 ;;
    k6) k6 version 2>&1 ;;
    go) go version 2>&1 ;;
    *) "$1" --version 2>&1 ;;
  esac | grep -Eq -- "$2"
}

# _m29d_prom_valeur 'PromQL' — première valeur (nombre) d'une requête instantanée, 0 si rien.
_m29d_prom_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo 0
}

# _m29d_superieur A B — A > B (nombres décimaux).
_m29d_superieur() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }
