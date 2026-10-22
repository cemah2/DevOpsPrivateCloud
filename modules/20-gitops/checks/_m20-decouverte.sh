# shellcheck shell=bash
# _m20-decouverte.sh — fonctions partagées par les checks M20-E02 à M20-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m20d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès :
#   - cluster : « kube » (check-lib.sh), compte de service wb-checks en lecture ; les objets
#     d'Argo CD (applications, appprojects, applicationsets) sont lisibles à partir de M20-E03
#     (extension de la ClusterRole agrégée wb-checks-livraison). Jamais de Secret par wb-checks.
#   - Secrets : seule l'EXISTENCE d'un Secret est lue, avec le kubeconfig personnel
#     (WB_K8S_ADMIN_KUBECONFIG, « get -o name », comme les exceptions du M17) : jamais son contenu.
#   - API d'Argo CD : GET seulement, avec le jeton du compte local « ci-lecture » (rôle readonly,
#     M20-E03), passé à curl par un fichier de configuration (jamais sur la ligne de commande).
#   - GitLab : gitlab_api (jeton read_api des checks, bloc A).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_ARGOCD_URL           https://argocd.apps.par1.medisphere.internal
#   WB_ARGOCD_TOKEN_FILE    ~/.config/workbook/argocd-checks.token
#   WB_K8S_ADMIN_KUBECONFIG ~/.kube/config (lecture de l'existence d'un Secret seulement)
#   WB_MOI                  ton compte (bloc A) ; ton compte local Argo CD est le même, points
#                           remplacés par des tirets (Argo CD refuse les points dans un nom de compte)

_M20D_ARGOCD_URL="${WB_ARGOCD_URL:-https://argocd.apps.par1.medisphere.internal}"
_M20D_ARGOCD_HOTE="${_M20D_ARGOCD_URL#https://}"
_M20D_ARGOCD_HOTE="${_M20D_ARGOCD_HOTE%%/*}"
_M20D_JETON="${WB_ARGOCD_TOKEN_FILE:-$HOME/.config/workbook/argocd-checks.token}"
_M20D_ADMIN_KCFG="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
_M20D_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M20D_NS=argocd
_M20D_IN_CLUSTER="https://kubernetes.default.svc"
_M20D_MOI="${WB_MOI:-}"
_M20D_MOI_ARGO="${_M20D_MOI//./-}"
# Argo CD de référence : 3.5.x (chart 10.10.x), PLAN §6.
_M20D_VERSION_RE='^v3\.5\.[0-9]+$'

# _m20d_k ARGS… — kubectl en lecture avec wb-checks (sortie sur stdout, vide en cas d'erreur).
_m20d_k() {
  kube "$@" 2>/dev/null || true
}

# _m20d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m20d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m20d_app NOM — Application NOM de l'espace argocd en JSON (vide si absente ou illisible).
_m20d_app() {
  _m20d_k -n "$_M20D_NS" get applications.argoproj.io "$1" -o json
}

# _m20d_projet NOM — AppProject NOM en JSON (vide si absent ou illisible).
_m20d_projet() {
  _m20d_k -n "$_M20D_NS" get appprojects.argoproj.io "$1" -o json
}

# _m20d_peut_lire_argo — wb-checks peut lister les Applications (extension de M20-E03).
_m20d_peut_lire_argo() {
  [[ "$(_m20d_k auth can-i list applications.argoproj.io -n "$_M20D_NS")" == "yes" ]]
}

# _m20d_argocd_api CHEMIN — GET sur l'API d'Argo CD (/api/v1/CHEMIN) avec le jeton ci-lecture.
#   Le jeton passe par un fichier de configuration curl (substitution de processus) : il
#   n'apparaît ni dans « ps » ni dans l'historique. TLS vérifié par le magasin système d'adm01.
_m20d_argocd_api() {
  [[ -r "$_M20D_JETON" ]] || { echo "jeton Argo CD des checks illisible : $_M20D_JETON" >&2; return 1; }
  curl -sf --max-time "${WB_TIMEOUT:-5}" \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '[:space:]' <"$_M20D_JETON")") \
    -H "Accept: application/json" "$_M20D_ARGOCD_URL/api/v1/$1"
}

# _m20d_secret_existe ESPACE NOM — « oui », « non » ou « ? » (API injoignable). Lit l'existence
#   seulement (-o name), avec le kubeconfig personnel : wb-checks n'a aucun droit sur les Secrets.
_m20d_secret_existe() {
  local sortie
  if ! sortie="$(kubectl --kubeconfig "$_M20D_ADMIN_KCFG" --request-timeout="${WB_TIMEOUT:-5}s" \
      -n "$1" get secret "$2" --ignore-not-found -o name 2>/dev/null)"; then
    echo "?"
  elif [[ -n "$sortie" ]]; then
    echo "oui"
  else
    echo "non"
  fi
}

# _m20d_uri TEXTE — encodage URL (chemins de projets GitLab).
_m20d_uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m20d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m20d_fichier_main() {
  gitlab_api "projects/$(_m20d_uri "$1")/repository/files/$(_m20d_uri "$2")?ref=main" >/dev/null 2>&1
}

# _m20d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m20d_contenu_main() {
  gitlab_api "projects/$(_m20d_uri "$1")/repository/files/$(_m20d_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m20d_url_depot PROJET — URL HTTPS de clonage attendue dans les Applications.
_m20d_url_depot() {
  printf '%s/%s.git' "$_M20D_GITLAB" "$1"
}

# _m20d_meme_depot URL PROJET — l'URL désigne le projet GitLab (avec ou sans « .git » final).
_m20d_meme_depot() {
  local url="${1%/}"
  url="${url%.git}"
  [[ "$url" == "$_M20D_GITLAB/$2" ]]
}

# _m20d_suivi OBJET_JSON — valeur de l'annotation de suivi d'Argo CD (vide si absente).
_m20d_suivi() {
  jq -r '.metadata.annotations["argocd.argoproj.io/tracking-id"] // ""' <<<"$1" 2>/dev/null || true
}

# _m20d_jetons_deploiement GROUPE — jetons de déploiement du groupe GitLab (JSON, vide si illisible).
_m20d_jetons_deploiement() {
  gitlab_api "groups/$(_m20d_uri "$1")/deploy_tokens?per_page=100" 2>/dev/null || true
}
