# shellcheck shell=bash
# _m20-operationnel.sh — fonctions partagées par les checks M20-E10 à M20-E23 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m20o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en LECTURE) :
#   - cluster : « kube » (check-lib.sh), compte wb-checks : Applications, ApplicationSets, AppProjects
#     (wb-checks-livraison étendue en M20-E03), objets d'Argo Rollouts (M20-E15), ConfigMaps ; jamais
#     les Secrets ;
#   - Argo CD : API REST avec le jeton du compte local ci-lecture (~/.config/workbook/argocd-checks.token,
#     M20-E03), passé par un fichier de configuration curl (jamais sur la ligne de commande) ;
#   - GitLab : gitlab_api (jeton read_api des checks) ; Harbor : harbor_api ; Mailpit : mailpit_api ;
#   - flux01 : SSH « admin », commandes de consultation (k3s kubectl get) sous sudo -n.

_m20o_brouillons="$HOME/m20"
_m20o_argocd_url="${WB_ARGOCD_URL:-https://argocd.apps.par1.medisphere.internal}"
_m20o_argocd_jeton="${WB_ARGOCD_TOKEN_FILE:-$HOME/.config/workbook/argocd-checks.token}"
_M20O_IMAGE_API="registry.par1.medisphere.internal/medisphere/mediagenda-api"

# --- Cluster (wb-checks) ------------------------------------------------------------------------
# _m20o_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m20o_k() { kube "$@" 2>/dev/null || true; }

# _m20o_obj ESPACE TYPE NOM — objet en JSON (vide si absent ou illisible).
_m20o_obj() { _m20o_k get "$2" "$3" -n "$1" -o json; }

# _m20o_app NOM — Application Argo CD (espace argocd) en JSON.
_m20o_app() { _m20o_obj argocd applications.argoproj.io "$1"; }

# _m20o_jq JSON FILTRE [ARGS jq…] — 0 si le filtre jq (-e) est vrai sur le JSON donné.
_m20o_jq() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" >/dev/null 2>&1 <<<"$donnees"
}

# _m20o_sync_sante JSON [SYNC] [SANTÉ] — Application au statut de synchro et de santé attendus
# (défauts : Synced, Healthy).
# shellcheck disable=SC2016  # filtre jq entre apostrophes
_m20o_sync_sante() {
  _m20o_jq "$1" '.status.sync.status == $s and .status.health.status == $h' \
    --arg s "${2:-Synced}" --arg h "${3:-Healthy}"
}

# _m20o_lisible TYPE [ESPACE] — wb-checks sait lister ce type (sinon : droits ou CRD absents).
_m20o_lisible() {
  if [[ -n "${2:-}" ]]; then kube get "$1" -n "$2" -o name >/dev/null 2>&1
  else kube get "$1" -A -o name >/dev/null 2>&1; fi
}

# --- Argo CD (API, jeton en lecture) ------------------------------------------------------------
# _m20o_argocd_api CHEMIN — GET /api/v1/CHEMIN (vide si jeton absent ou erreur).
_m20o_argocd_api() {
  [[ -r "$_m20o_argocd_jeton" ]] || return 1
  curl -sf --max-time "$WB_TIMEOUT" \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$_m20o_argocd_jeton")") \
    -H "Accept: application/json" "$_m20o_argocd_url/api/v1/$1" 2>/dev/null
}

# --- GitLab -------------------------------------------------------------------------------------
_m20o_enc() { jq -rn --arg s "$1" '$s | @uri'; }

# _m20o_gl_fichier PROJET CHEMIN [RÉF] — contenu brut sur la branche (défaut main), vide si absent.
_m20o_gl_fichier() {
  gitlab_api "projects/$(_m20o_enc "$1")/repository/files/$(_m20o_enc "$2")/raw?ref=${3:-main}" 2>/dev/null || true
}
_m20o_gl_existe() { [[ -n "$(_m20o_gl_fichier "$@" | head -c 1)" ]]; }

# _m20o_gl_arbre PROJET [CHEMIN] — chemins des fichiers de main (récursif, 100 par page, 5 pages).
_m20o_gl_arbre() {
  local p page
  p="projects/$(_m20o_enc "$1")/repository/tree?ref=main&recursive=true&per_page=100"
  [[ -n "${2:-}" ]] && p="$p&path=$(_m20o_enc "$2")"
  for page in 1 2 3 4 5; do
    gitlab_api "$p&page=$page" 2>/dev/null | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
  done | sort -u
}

# _m20o_pipeline_ok PROJET [RÉF] — le dernier pipeline de la branche (défaut main) a réussi.
_m20o_pipeline_ok() {
  gitlab_api "projects/$(_m20o_enc "$1")/pipelines?ref=${2:-main}&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m20o_mr_fusionnees PROJET — JSON des 100 dernières MR fusionnées vers main.
_m20o_mr_fusionnees() {
  gitlab_api "projects/$(_m20o_enc "$1")/merge_requests?state=merged&target_branch=main&per_page=100" 2>/dev/null || true
}

# --- Harbor -------------------------------------------------------------------------------------
# _m20o_harbor_signe PROJET DÉPÔT ÉTIQUETTE — l'artefact existe et porte au moins un accessoire
# (signature Cosign, référent OCI).
_m20o_harbor_signe() {
  local depot
  depot="$(_m20o_enc "$2")"
  harbor_api "projects/$1/repositories/$depot/artifacts?with_tag=true&with_accessory=true&page_size=100" 2>/dev/null \
    | jq -e --arg t "$3" '[.[] | select([.tags[]?.name] | index($t)) | (.accessories // []) | length] | any(. > 0)' >/dev/null 2>&1
}

# --- Fichiers locaux ----------------------------------------------------------------------------
# _m20o_fichier_contient FICHIER REGEX — fichier présent qui contient la regex (étendue, insensible à la casse).
_m20o_fichier_contient() { [[ -s "$1" ]] && grep -Eiq -- "$2" "$1"; }

# _m20o_yaml_json FICHIER… — documents YAML en un tableau JSON (yq 4 de mikefarah), [] si erreur.
_m20o_yaml_json() {
  local f sortie=""
  for f in "$@"; do
    [[ -r "$f" ]] || continue
    sortie+="$(yq -o json -I0 '.' "$f" 2>/dev/null)"$'\n' || true
  done
  jq -s 'map(select(. != null))' <<<"$sortie" 2>/dev/null || echo '[]'
}
