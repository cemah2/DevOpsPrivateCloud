# shellcheck shell=bash
# _m20-production.sh — fonctions partagées par les checks M20-E24 à M20-E34 (lecture seule).
# Sourcé par les check-EXX.sh du palier 3 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m20p_ / _M20P_ : pas de collision avec les autres paliers (_m20d_, _m20o_, _m20x_).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Accès (tous en LECTURE) :
#   - cluster k8s-par1 : « kube » (compte wb-checks ; objets d'Argo CD et d'Argo Rollouts lisibles
#     depuis M20-E03 et M20-E15 par wb-checks-livraison ; jamais les Secrets) ;
#   - API d'Argo CD : GET avec le jeton du compte local ci-lecture (role:lecture, M20-E24) ;
#   - GitLab : gitlab_api (jeton read_api des checks) ;
#   - lyo-k3s01 (M20-E26) : SSH « admin » et « sudo -n k3s kubectl get … » (lecture) ;
#   - pve01 : « qm config » (lecture) ; s3-01 : identité argocd-sauvegardes (liste et 16 premiers
#     octets d'un objet) ; Mailpit : mailpit_api.
# La politique RBAC est évaluée HORS LIGNE par la CLI argocd (« admin settings rbac can ») sur le
# ConfigMap lu par wb-checks : aucun appel à l'API d'Argo CD pour cela, aucune écriture.
#
# Variables de lab/lab.env (défauts ci-dessous) :
#   WB_ARGOCD_URL, WB_ARGOCD_TOKEN_FILE (communes au module) ; WB_MOI (ton compte, bloc A) ;
#   WB_M20_LYO (hôte SSH de lyo-k3s01) ; WB_M20_S3_SAUVEGARDES_ENV (identité S3 des sauvegardes) ;
#   WB_M20_E34_T0 (fichier T0 de l'exercice chronométré) ; WB_S3_ENDPOINT ; WB_PVE_HOST.

_M20P_URL="${WB_ARGOCD_URL:-https://argocd.apps.par1.medisphere.internal}"
_M20P_JETON="${WB_ARGOCD_TOKEN_FILE:-$HOME/.config/workbook/argocd-checks.token}"
_M20P_NS=argocd
_M20P_MOI="${WB_MOI:-}"
# Compte local Argo CD : points remplacés par des tirets (accounts.<nom> découpé sur les points).
_M20P_MOI_ARGO="${_M20P_MOI//./-}"
_M20P_LYO="${WB_M20_LYO:-lyo-k3s01}"
_M20P_LYO_SERVEUR="https://lyo-k3s01.par1.medisphere.internal:6443"
_M20P_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M20P_S3_ENV="${WB_M20_S3_SAUVEGARDES_ENV:-$HOME/.config/workbook/s3-argocd-sauvegardes.env}"
_M20P_TMP=""

# _m20p_init_tmp — crée le dossier temporaire (700) du check et son nettoyage à la sortie. À appeler
# dans le shell PRINCIPAL du check (pas dans « $(…) » : un sous-shell effacerait le dossier en sortant).
_m20p_init_tmp() {
  if [[ -z "$_M20P_TMP" ]]; then
    _M20P_TMP="$(mktemp -d)"
    # shellcheck disable=SC2064  # le chemin est figé au moment de l'appel, voulu
    trap "rm -rf '$_M20P_TMP'" EXIT
  fi
}

# _m20p_tmp — chemin du dossier temporaire (créé par _m20p_init_tmp).
_m20p_tmp() {
  [[ -n "$_M20P_TMP" && -d "$_M20P_TMP" ]] || return 1
  printf '%s\n' "$_M20P_TMP"
}

# --- API Kubernetes (compte wb-checks) ------------------------------------------------------------

# _m20p_json ARGS… — sortie JSON valide de « kube ARGS -o json », ou « null ».
_m20p_json() {
  local s
  s="$(kube "$@" -o json 2>/dev/null)" || s=""
  if [[ -n "$s" ]] && jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m20p_jq JSON FILTRE [ARGS jq…] — filtre booléen jq (null → faux).
_m20p_jq() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" && "$donnees" != null ]] && jq -e "$@" "$filtre" >/dev/null 2>&1 <<<"$donnees"
}

_m20p_joignable() { [[ "$(kube get --raw /readyz 2>/dev/null)" == ok ]]; }

# _m20p_app NOM / _m20p_projet NOM / _m20p_cm NOM — objets de l'espace argocd (JSON ou null).
_m20p_app() { _m20p_json -n "$_M20P_NS" get applications.argoproj.io "$1"; }
_m20p_projet() { _m20p_json -n "$_M20P_NS" get appprojects.argoproj.io "$1"; }
_m20p_cm() { _m20p_json -n "$_M20P_NS" get configmap "$1"; }

# _m20p_app_saine JSON — Application Synced et Healthy.
_m20p_app_saine() {
  _m20p_jq "$1" '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
}

# _m20p_epoch DATE — secondes depuis l'époque (vide si illisible).
_m20p_epoch() { [[ -n "${1:-}" && "$1" != null ]] && date -d "$1" +%s 2>/dev/null; }

# _m20p_duree_s DURÉE_GO — « 8h », « 90m », « 300s », « 8h0m0s » → secondes (vide si illisible).
_m20p_duree_s() {
  local d="${1:-}" total=0 n u
  [[ "$d" =~ ^([0-9]+[hms])+$ ]] || return 1
  while [[ "$d" =~ ^([0-9]+)([hms])(.*)$ ]]; do
    n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"; d="${BASH_REMATCH[3]}"
    case "$u" in h) total=$((total + n * 3600)) ;; m) total=$((total + n * 60)) ;; s) total=$((total + n)) ;; esac
  done
  echo "$total"
}

# --- API d'Argo CD (jeton ci-lecture) -------------------------------------------------------------

# _m20p_argocd_api CHEMIN — GET /api/v1/CHEMIN ; le jeton passe par un fichier de configuration curl.
_m20p_argocd_api() {
  [[ -r "$_M20P_JETON" ]] || { echo "jeton Argo CD des checks illisible : $_M20P_JETON" >&2; return 1; }
  curl -sf --max-time "${WB_TIMEOUT:-5}" \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '[:space:]' <"$_M20P_JETON")") \
    -H "Accept: application/json" "$_M20P_URL/api/v1/$1"
}

# --- RBAC hors ligne (CLI argocd) ------------------------------------------------------------------

# _m20p_rbac_fichier — écrit argocd-rbac-cm (JSON, lu par wb-checks) dans le dossier temporaire et
# affiche son chemin ; échoue si le ConfigMap est illisible.
_m20p_rbac_fichier() {
  local t cm
  t="$(_m20p_tmp)" || return 1
  cm="$(_m20p_cm argocd-rbac-cm)"
  [[ "$cm" != null ]] || return 1
  printf '%s\n' "$cm" >"$t/argocd-rbac-cm.json"
  # Kubeconfig FACTICE : la commande en exige un même avec --policy-file ; aucune connexion n'est faite.
  cat >"$t/factice.kubeconfig" <<'EOF'
apiVersion: v1
kind: Config
clusters:
  - name: aucun
    cluster: {server: "https://127.0.0.1:9"}
contexts:
  - name: aucun
    context: {cluster: aucun, user: aucun, namespace: argocd}
current-context: aucun
users:
  - name: aucun
    user: {token: factice}
EOF
  printf '%s\n' "$t/argocd-rbac-cm.json"
}

# _m20p_rbac_peut FICHIER SUJET ACTION RESSOURCE OBJET — « Yes », « No » ou vide (erreur).
_m20p_rbac_peut() {
  local f="$1"
  shift
  KUBECONFIG="$(dirname "$f")/factice.kubeconfig" timeout 30 \
    argocd admin settings rbac can "$@" --policy-file "$f" </dev/null 2>/dev/null || true
}

# --- GitLab (jeton des checks, lecture) ------------------------------------------------------------

_m20p_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m20p_fichier_main PROJET CHEMIN — contenu brut sur main (vide si absent).
_m20p_fichier_main() {
  gitlab_api "projects/$(_m20p_uri "$1")/repository/files/$(_m20p_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m20p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif
# (expressions étendues, sans tenir compte de la casse).
_m20p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m20p_fichier_main "$p" "$chemin")"
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m20p_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main, jusqu'à 1000.
_m20p_arbre() {
  local p d page=1 s
  p="$(_m20p_uri "$1")"
  d="${2:+&path=$(_m20p_uri "$2")}"
  while (( page <= 10 )); do
    s="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page$d" 2>/dev/null)" || break
    [[ -n "$s" && "$s" != "[]" ]] || break
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$s" 2>/dev/null || break
    page=$((page + 1))
  done
}

# _m20p_dernier_pipeline PROJET — dernier pipeline de main (JSON ou null).
_m20p_dernier_pipeline() {
  local s
  s="$(gitlab_api "projects/$(_m20p_uri "$1")/pipelines?ref=main&per_page=1&order_by=id&sort=desc" 2>/dev/null \
    | jq -c '.[0] // null' 2>/dev/null)" || s=null
  printf '%s\n' "${s:-null}"
}

# _m20p_jobs PROJET PIPELINE — jobs du pipeline (JSON, [] si illisible).
_m20p_jobs() {
  local s
  s="$(gitlab_api "projects/$(_m20p_uri "$1")/pipelines/$2/jobs?per_page=100&include_retried=false" 2>/dev/null)" || s="[]"
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$s" || s="[]"
  printf '%s\n' "$s"
}

# _m20p_doc PROJET CHEMIN REGEX… — raccourci pour la documentation de plateforme/medisphere.
_m20p_doc() { _m20p_fichier_contient plateforme/medisphere "$@"; }

# --- lyo-k3s01 (SSH, sudo -n, lecture) --------------------------------------------------------------

# _m20p_lyo ARGS… — « k3s kubectl ARGS -o json » sur lyo-k3s01 (JSON ou null).
_m20p_lyo() {
  local s
  s="$(remote "$_M20P_LYO" "sudo -n /usr/local/bin/k3s kubectl $* -o json" 2>/dev/null)" || s=""
  if [[ -n "$s" ]] && jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# --- Stockage objet (identité argocd-sauvegardes) ------------------------------------------------------

_m20p_s3() {
  [[ -r "$_M20P_S3_ENV" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M20P_S3_ENV"
    set +a
    exec aws --endpoint-url "$_M20P_S3" --output json "$@" </dev/null
  )
}
