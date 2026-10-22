# shellcheck shell=bash
# _m19-decouverte.sh — fonctions partagées par les checks M19-E02 à M19-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m19d_ : pas de collision avec les fonctions des autres paliers (_m19o_, _m19p_, _m19x_).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en LECTURE) :
#   - Kubernetes : « kube » (check-lib.sh), compte de service wb-checks (ClusterRole agrégée, dont
#     wb-checks-livraison créée en M19-E02), jamais les Secrets ;
#   - GitLab : « gitlab_api » (jeton read_api + admin_mode des checks, M01) ;
#   - Harbor : « harbor_api » (robot wb-checks, M13) ; Mailpit : « mailpit_api » (compte wb-checks, M19-E03) ;
#   - Proxmox : « qm config » / « pvesm list » en root sur pve01 ; nœuds et VMs : SSH, commandes de
#     consultation seulement (sudo -n pour lire un fichier réservé à root) ;
#   - s3-01 : requêtes S3 signées en GET avec l'identité ci-cache (M19-E07).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_K8S_KUBECONFIG, WB_K8S_WORKERS, WB_K8S_CP     (bloc C)
#   WB_M19_LABO          projet d'exercice (formation/ci-labo)
#   WB_M19_MON01         alias SSH de mon01 (mon01)
#   WB_S3_CI_CACHE_FILE  identité ci-cache (~/.config/workbook/s3-ci-cache.env)
#   WB_MAILPIT_URL, WB_MAILPIT_CHECKS_FILE (check-lib.sh)
#   WB_PBS_STORAGE       stockage PBS de pve01 (pbs-par2)
#   WB_RACINE_PKI        racine MédiSphère sur adm01

read -r -a _M19D_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M19D_LABO="${WB_M19_LABO:-formation/ci-labo}"
_M19D_MON01="${WB_M19_MON01:-mon01}"
_M19D_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M19D_HARBOR="registry.par1.medisphere.internal"
_M19D_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M19D_S3_ENV="${WB_S3_CI_CACHE_FILE:-$HOME/.config/workbook/s3-ci-cache.env}"
_M19D_RUNNER="k8s-par1"

# Table du plan : travailleur → VMID (PLAN §4.10).
declare -A _M19D_VMID=([k8s-cp01]=2141 [k8s-cp02]=2142 [k8s-cp03]=2143 [k8s-w01]=2144 [k8s-w02]=2145 [k8s-w03]=2146)

# _m19d_kj ARGS… — « kube … -o json » ; sortie vide si l'objet est absent ou illisible.
_m19d_kj() {
  kube "$@" -o json 2>/dev/null || true
}

# _m19d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m19d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m19d_enc TEXTE — encodage URL (chemins de projets et de fichiers pour l'API GitLab).
_m19d_enc() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m19d_api CHEMIN — GET sur l'API GitLab ; vide en cas d'échec.
_m19d_api() {
  gitlab_api "$1" 2>/dev/null || true
}

# _m19d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m19d_contenu_main() {
  _m19d_api "projects/$(_m19d_enc "$1")/repository/files/$(_m19d_enc "$2")/raw?ref=main"
}

# _m19d_fichier_main PROJET CHEMIN — le fichier existe sur main.
_m19d_fichier_main() {
  gitlab_api "projects/$(_m19d_enc "$1")/repository/files/$(_m19d_enc "$2")?ref=main" >/dev/null 2>&1
}

# _m19d_arbre_main PROJET — chemins des fichiers de main (un par ligne, 5 pages de 100 au plus).
_m19d_arbre_main() {
  local p page
  p="$(_m19d_enc "$1")"
  for page in 1 2 3 4 5; do
    _m19d_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page" \
      | jq -r '.[]? | select(.type == "blob") | .path' 2>/dev/null || true
  done
}

# _m19d_grep_main PROJET MOTIF_CHEMIN REGEX — un fichier de main dont le chemin correspond au motif
# (regex étendue) contient REGEX. Lit au plus 20 fichiers.
_m19d_grep_main() {
  local projet="$1" motif="$2" regex="$3" f n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n=$((n + 1))
    ((n <= 20)) || break
    if _m19d_contenu_main "$projet" "$f" | grep -Eq -- "$regex"; then
      return 0
    fi
  done < <(_m19d_arbre_main "$projet" | grep -E -- "$motif" || true)
  return 1
}

# _m19d_vault_critique PROJET CHEMIN — le fichier de main est chiffré sous l'identité « critique ».
_m19d_vault_critique() {
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête Ansible Vault
  _m19d_contenu_main "$1" "$2" | head -n 1 | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique$'
}

# _m19d_pipelines PROJET [PARAMÈTRES] — JSON des pipelines (récents d'abord).
_m19d_pipelines() {
  _m19d_api "projects/$(_m19d_enc "$1")/pipelines?order_by=id&sort=desc&${2:-per_page=20}"
}

# _m19d_jobs PROJET PIPELINE — JSON des jobs d'un pipeline (100 au plus).
_m19d_jobs() {
  _m19d_api "projects/$(_m19d_enc "$1")/pipelines/$2/jobs?per_page=100"
}

# _m19d_trace PROJET JOB — journal brut d'un job.
_m19d_trace() {
  _m19d_api "projects/$(_m19d_enc "$1")/jobs/$2/trace"
}

# _m19d_runner_id — identifiant du runner d'instance « k8s-par1 » (vide si absent).
_m19d_runner_id() {
  _m19d_api "runners/all?type=instance_type&per_page=100" \
    | jq -r --arg d "$_M19D_RUNNER" '[.[]? | select(.description == $d)][0].id // empty' 2>/dev/null || true
}

# _m19d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m19d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m19d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m19d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m19d_s3_get CHEMIN — GET signé (AWS SigV4) sur s3-01 avec l'identité ci-cache ; corps sur la
# sortie standard, code HTTP en dernière ligne. Les clés passent par un fichier de configuration
# curl lu sur un descripteur (jamais sur la ligne de commande).
_m19d_s3_get() {
  local AWS_ACCESS_KEY_ID="" AWS_SECRET_ACCESS_KEY=""
  [[ -r "$_M19D_S3_ENV" ]] || return 1
  # shellcheck disable=SC1090
  source "$_M19D_S3_ENV"
  curl -s --max-time "${WB_TIMEOUT:-5}" --aws-sigv4 "aws:amz:us-east-1:s3" \
    -K <(printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY") \
    -w '\n%{http_code}\n' "$_M19D_S3/$1" 2>/dev/null || true
}

# _m19d_local600 FICHIER — le fichier existe et est en 600.
_m19d_local600() {
  [[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]
}
