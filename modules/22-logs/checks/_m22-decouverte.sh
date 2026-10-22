# shellcheck shell=bash
# _m22-decouverte.sh — fonctions partagées par les checks M22-E02 à M22-E05 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m22d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (PLAN §4.11) :
#   - Loki : loki_api / loki_requete (check-lib.sh), Service 10.10.41.62:3100 depuis MGMT, lecture ;
#   - cluster : « kube » (compte wb-checks, jamais les Secrets) ; Applications Argo CD par kube ;
#   - GitLab : gitlab_api (jeton read_api des checks) ;
#   - compartiment loki-k8s-par1 : ~/.config/workbook/s3-loki.env, LISTE seulement (aws s3api).

_M22D_NS=journaux
_M22D_LOKI_IP=10.10.41.62
_M22D_BUCKET=loki-k8s-par1
_M22D_S3_ENV="${WB_M22_S3_LOKI_ENV:-$HOME/.config/workbook/s3-loki.env}"
_M22D_RGW_URL="${WB_M22_RGW_URL:-https://rgw.par1.medisphere.internal}"
_M22D_P_OBS="projects/plateforme%2Fobservabilite"
_M22D_P_DOC="projects/plateforme%2Fmedisphere"
_M22D_P_GITOPS="projects/plateforme%2Fgitops"
_M22D_LOCATAIRES=(plateforme mediagenda medidoc audit)
# Étiquettes Loki autorisées (liste fermée, PLAN §4.11) ; host, role, site pour les VMs.
_M22D_ETIQUETTES_OK='^(cluster|namespace|app|container|node|job|host|role|site)$'
# VMs du socle qui doivent envoyer leur journal (M22-E05) ; à adapter si ton socle diffère.
read -r -a _M22D_VMS <<<"${WB_M22_VMS_SOCLE:-gw01 gw02 adm01 dns01 dns02 ca01 git01 runner01 runner02 nbx01 s3-01 reg01 mon01 lb01 lb02}"

# _m22d_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m22d_k() { kube "$@" 2>/dev/null || true; }

# _m22d_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m22d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m22d_app NOM — Application Argo CD (JSON), vide si absente ou illisible.
_m22d_app() { _m22d_k get applications.argoproj.io -n argocd "$1" -o json; }

# _M22D_APP_SAINE — filtre jq : Application synchronisée et saine.
# shellcheck disable=SC2016
_M22D_APP_SAINE='.status.sync.status == "Synced" and .status.health.status == "Healthy"'

# _m22d_requete 'LogQL' LOCATAIRE [DEPUIS=1h] — JSON de query_range (vide si erreur).
_m22d_requete() { loki_requete "$1" "${2:-plateforme}" "${3:-1h}" 2>/dev/null || true; }

# _m22d_nb_resultats 'LogQL' LOCATAIRE [DEPUIS] — nombre de flux ou de séries renvoyés (0 si erreur).
_m22d_nb_resultats() {
  local r
  r="$(_m22d_requete "$@")"
  jq -r 'if .status == "success" then (.data.result | length) else 0 end' <<<"${r:-{\}}" 2>/dev/null || echo 0
}

# _m22d_somme 'LogQL métrique' LOCATAIRE [DEPUIS] — somme des dernières valeurs des séries (0 si rien).
_m22d_somme() {
  local r
  r="$(_m22d_requete "$@")"
  jq -r '[.data.result[]? | (.values[-1][1] | tonumber)] | add // 0' <<<"${r:-{\}}" 2>/dev/null || echo 0
}

# _m22d_etiquettes LOCATAIRE [DEPUIS=1h] — noms d'étiquettes INDEXÉES (une par ligne). Les
# métadonnées structurées n'apparaissent pas dans cette API : c'est ce qui les distingue.
_m22d_etiquettes() {
  loki_api "labels?since=${2:-1h}" "$1" 2>/dev/null | jq -r '.data[]?' 2>/dev/null || true
}

# _m22d_hors_liste LOCATAIRE [DEPUIS] — étiquettes indexées hors de la liste fermée (vide si aucune).
_m22d_hors_liste() {
  _m22d_etiquettes "$@" | grep -Ev -- "$_M22D_ETIQUETTES_OK" | grep -v '^$' | paste -sd, - || true
}

# _m22d_fichier_main PROJET CHEMIN — le fichier existe sur main du projet GitLab.
_m22d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}

# _m22d_contenu_main PROJET CHEMIN [BRANCHE=main] — contenu brut du fichier (vide si absent).
_m22d_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m22d_s3_cles [PRÉFIXE] — clés du compartiment loki-k8s-par1 (au plus 50), une par ligne.
#   Identifiants lus dans s3-loki.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), dans un sous-shell.
_m22d_s3_cles() {
  [[ -r "$_M22D_S3_ENV" ]] || return 0
  (
    set -a
    # shellcheck disable=SC1090
    source "$_M22D_S3_ENV"
    set +a
    aws --endpoint-url "$_M22D_RGW_URL" s3api list-objects-v2 --bucket "$_M22D_BUCKET" \
      --prefix "${1:-}" --max-items 50 --query 'Contents[].Key' --output text 2>/dev/null
  ) | tr '\t' '\n' | grep -v -e '^None$' -e '^$' || true
}

# _m22d_age_min NS SÉLECTEUR — âge en minutes du plus jeune pod qui correspond (vide si aucun).
_m22d_age_min() {
  _m22d_k get pods -n "$1" -l "$2" -o json \
    | jq -r '[.items[].status.startTime // empty | fromdateiso8601] | if length > 0 then ((now - max) / 60 | floor) else empty end' 2>/dev/null || true
}
