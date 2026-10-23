# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et requêtes PromQL entre apostrophes
# _m28-decouverte.sh — fonctions partagées par les vérifications des paliers 1 et 2 du module 28
# (check-E02 à check-E12) ; réutilisables par les paliers 3, 4 et le mini-projet. Sourcé, jamais lancé seul.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Lecture seule : « kube » (compte wb-checks, sans les Secrets ; ClusterRole agrégée
# wb-checks-services-m28 pour keda.sh, autoscaling.k8s.io, capsule.clastix.io, external.metrics.k8s.io),
# Prometheus / Thanos Query (GET), GitLab (jeton read_api), API du catalogue de Backstage (jeton
# d'accès externe en lecture), stockage objet en liste/lecture (identité de lecture).
# Seule « écriture » : des SubjectAccessReview (question posée à l'apiserver, rien n'est enregistré).
# Préfixe _m28d_ : pas de collision avec les autres paliers quand un check en charge plusieurs.
#
# Variables de lab/lab.env (facultatives) :
#   WB_M28_S3_TECHDOCS   identité de lecture de portail-techdocs (défaut : ~/.config/workbook/s3-techdocs.env)
#   WB_M28_PORTAIL_URL   adresse du portail (défaut : https://portail.apps.par1.medisphere.internal)
#   WB_S3_ENDPOINT       point d'accès de s3-01 (défaut : https://s3-01.par1.medisphere.internal:8333)

# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m28d_portail="${WB_M28_PORTAIL_URL:-https://portail.apps.par1.medisphere.internal}"
  _m28d_s3_techdocs="${WB_M28_S3_TECHDOCS:-$HOME/.config/workbook/s3-techdocs.env}"
  _m28d_s3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
  _m28d_harbor_re='^registry\.par1\.medisphere\.internal/'
}

# --- Kubernetes ---------------------------------------------------------------------------------

# _m28d_json ARGS… — JSON de « kube get ARGS -o json », « null » en cas d'erreur.
_m28d_json() {
  local s
  s="$(kube get "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m28d_kq 'filtre jq' ARGS… [-- options jq] — 0 si « kube get ARGS -o json » satisfait le filtre.
# Les options jq (ex. --arg n v) se placent après « -- ».
_m28d_kq() {
  local f="$1" args=() opts=()
  shift
  while (($#)); do
    if [[ "$1" == "--" ]]; then
      shift
      opts=("$@")
      break
    fi
    args+=("$1")
    shift
  done
  kube get "${args[@]}" -o json 2>/dev/null | jq -e "${opts[@]}" "$f" >/dev/null 2>&1
}

# _m28d_existe ARGS… — l'objet existe (kube get réussit).
_m28d_existe() { kube get "$@" -o name >/dev/null 2>&1; }

# _m28d_absent TYPE NOM [ESPACE] — l'API a RÉPONDU et l'objet n'est pas dans la liste (une erreur
# d'accès n'est jamais prise pour une absence).
_m28d_absent() {
  local type="$1" nom="$2" ns="${3:-}" l
  if [[ -n "$ns" ]]; then
    l="$(kube get "$type" -n "$ns" -o json 2>/dev/null)" || return 1
  else
    l="$(kube get "$type" -o json 2>/dev/null)" || return 1
  fi
  jq -e --arg n "$nom" '.items | map(.metadata.name) | index($n) == null' >/dev/null 2>&1 <<<"$l"
}

# _m28d_app_saine NOM — Application Argo CD Synced et Healthy.
_m28d_app_saine() {
  _m28d_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _m28d_app_synced NOM — Application Argo CD Synced (santé indifférente).
_m28d_app_synced() {
  _m28d_kq '.status.sync.status == "Synced"' -n argocd applications.argoproj.io "$1"
}

# _m28d_deploy_pret ESPACE NOM REGEX_IMAGE — Deployment disponible, à jour, image du premier
# conteneur conforme à la regex.
_m28d_deploy_pret() {
  _m28d_kq '(.status.availableReplicas // 0) >= 1 and (.status.updatedReplicas // 0) == (.spec.replicas // 1)
            and (.spec.template.spec.containers[0].image | test($re))' -n "$1" deployment "$2" -- --arg re "$3"
}

# _m28d_proprietaire_replicas ESPACE RESSOURCE NOM — liste (une ligne par gestionnaire) des gestionnaires
# de champs qui possèdent spec.replicas de l'objet.
_m28d_proprietaires_replicas() {
  kube get -n "$1" "$2" "$3" -o json --show-managed-fields 2>/dev/null |
    jq -r '.metadata.managedFields[]? | select(.fieldsV1["f:spec"]["f:replicas"] != null) | .manager' 2>/dev/null || true
}

# _m28d_replicas_hors_argocd ESPACE RESSOURCE NOM — l'objet existe et Argo CD ne possède PAS spec.replicas
# (Git ne le déclare plus, ou un autoscaler l'a repris).
_m28d_replicas_hors_argocd() {
  _m28d_existe -n "$1" "$2" "$3" || return 1
  ! grep -qx 'argocd-controller' <<<"$(_m28d_proprietaires_replicas "$1" "$2" "$3")"
}

# _m28d_peut UTILISATEUR GROUPE VERBE RESSOURCE ESPACE [GROUPE_API] — l'apiserver répond « allowed »
# à la question (SubjectAccessReview). Code 1 si refusé, 2 si l'API n'a pas répondu.
_m28d_peut() {
  local r
  r="$(jq -cn --arg u "$1" --arg g "$2" --arg v "$3" --arg res "$4" --arg ns "$5" --arg ga "${6:-}" '{
    apiVersion: "authorization.k8s.io/v1", kind: "SubjectAccessReview",
    spec: {user: $u, groups: [$g, "system:authenticated"],
           resourceAttributes: {verb: $v, resource: $res, namespace: $ns, group: $ga}}}' |
    kube create -f - -o json 2>/dev/null)" || return 2
  jq -e '.status.allowed == true' >/dev/null 2>&1 <<<"$r"
}

# _m28d_ne_peut_pas … — mêmes arguments ; l'apiserver a RÉPONDU et refuse.
_m28d_ne_peut_pas() {
  local c=0
  _m28d_peut "$@" || c=$?
  ((c == 1))
}

# --- Prometheus (Thanos Query) ---------------------------------------------------------------------

# _m28d_prom_positif 'PromQL' — au moins une série de valeur strictement positive.
_m28d_prom_positif() {
  prom_requete "$1" 2>/dev/null |
    jq -e '[.data.result[]?.value[1] | tonumber | select(. > 0)] | length > 0' >/dev/null 2>&1
}

# _m28d_prom_nul 'PromQL' — Prometheus a RÉPONDU, au moins une série, et aucune n'est > 0.
_m28d_prom_nul() {
  local r
  r="$(prom_requete "$1" 2>/dev/null)" || return 1
  jq -e '.status == "success" and (.data.result | length > 0)
         and ([.data.result[].value[1] | tonumber | select(. > 0)] | length == 0)' >/dev/null 2>&1 <<<"$r"
}

# --- GitLab (lecture) ----------------------------------------------------------------------------

_m28d_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# _m28d_fichier PROJET CHEMIN [REF=main] — contenu brut du fichier (code ≠ 0 s'il est absent).
_m28d_fichier() {
  gitlab_api "projects/$(_m28d_enc "$1")/repository/files/$(_m28d_enc "$2")/raw?ref=${3:-main}"
}

# _m28d_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif (casse ignorée).
_m28d_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m28d_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m28d_ne_contient_pas PROJET CHEMIN REGEX — le fichier existe et ne contient PAS le motif.
_m28d_ne_contient_pas() {
  local c
  c="$(_m28d_fichier "$1" "$2" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  ! grep -Eqi -- "$3" <<<"$c"
}

# _m28d_pipeline_vert PROJET — le dernier pipeline de main est « success ».
_m28d_pipeline_vert() {
  gitlab_api "projects/$(_m28d_enc "$1")/pipelines?ref=main&per_page=1" 2>/dev/null |
    jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m28d_doc CHEMIN REGEX… — document de plateforme/medisphere sur main, avec chaque motif.
_m28d_doc() {
  local chemin="$1"
  shift
  _m28d_contient plateforme/medisphere "$chemin" "$@"
}
