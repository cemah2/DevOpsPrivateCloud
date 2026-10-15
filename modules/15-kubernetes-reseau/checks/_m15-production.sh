# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes
# _m15-production.sh — fonctions partagées par les checks M15-E24 à M15-E34 (lecture seule).
# Sourcé par les check-EXX.sh du palier 3 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m15p_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Accès : « kube » (compte de service wb-checks, lecture, sans les Secrets), SSH « admin » + « sudo -n »
# vers les nœuds et les passerelles pour LIRE l'état du noyau (ip, ss), API GitLab en GET, requêtes
# DNS et HTTPS de test depuis adm01 (vérifiées contre la racine MédiSphère, jamais -k).
# Variables de lab/lab.env : WB_K8S_KUBECONFIG, WB_K8S_CP, WB_K8S_WORKERS (module 14), WB_GITLAB_*.

_M15P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M15P_DNS=(10.10.20.10 10.10.20.16)
_M15P_PASSERELLES=(gw01 gw02)
_M15P_GW_IP=10.10.41.10
_M15P_APPS=apps.par1.medisphere.internal
_M15P_VERSION_MIN=1.20.2
read -r -a _M15P_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M15P_WORKERS <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M15P_NOEUDS=("${_M15P_CP[@]}" "${_M15P_WORKERS[@]}")

# --- Kubernetes --------------------------------------------------------------------------------------

# _m15p_get ARGS… — « kube get ARGS -o json » ; sortie vide si l'objet n'existe pas ou si l'API ne répond pas.
_m15p_get() {
  kube get "$@" -o json 2>/dev/null || true
}

# _m15p_jq JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné (non vide).
_m15p_jq() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m15p_absent ARGS… — OK si « kube get ARGS » répond NotFound (un cluster injoignable n'est pas une absence).
_m15p_absent() {
  local sortie
  sortie="$(kube get "$@" 2>&1)" && return 1
  grep -q 'NotFound' <<<"$sortie"
}

# _m15p_api_ok — l'API répond avec l'identité des checks.
_m15p_api_ok() { kube get --raw /readyz 2>/dev/null | grep -qx ok; }

# _m15p_cilium_cfg CLÉ — valeur d'une clé de kube-system/cilium-config (vide si absente).
_m15p_cilium_cfg() {
  kube -n kube-system get configmap cilium-config -o json 2>/dev/null \
    | jq -r --arg k "$1" '.data[$k] // ""' 2>/dev/null || true
}

# _m15p_ds_pret ESPACE NOM — DaemonSet complet : prévus > 0, tous prêts, tous à jour.
_m15p_ds_pret() {
  _m15p_jq "$(_m15p_get -n "$1" daemonset "$2")" \
    '.status | (.desiredNumberScheduled // 0) > 0 and .numberReady == .desiredNumberScheduled and (.updatedNumberScheduled // 0) == .desiredNumberScheduled'
}

# _m15p_deploy_pret ESPACE NOM [MIN] — Deployment prêt (readyReplicas = replicas ≥ MIN, défaut 1).
_m15p_deploy_pret() {
  _m15p_jq "$(_m15p_get -n "$1" deployment "$2")" \
    '(.spec.replicas // 1) >= $m and (.status.readyReplicas // 0) == (.spec.replicas // 1)' --argjson m "${3:-1}"
}

# _m15p_ip_noeud NOM — adresse InternalIP d'un nœud.
_m15p_ip_noeud() {
  kube get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true
}

# _m15p_nb_noeuds — nombre de nœuds du cluster (0 si l'API ne répond pas).
_m15p_nb_noeuds() {
  kube get nodes -o json 2>/dev/null | jq '.items | length' 2>/dev/null || echo 0
}

# _m15p_ns_label ESPACE CLÉ VALEUR — l'espace porte le label CLÉ=VALEUR.
_m15p_ns_label() {
  _m15p_jq "$(_m15p_get namespace "$1")" '.metadata.labels[$k] == $v' --arg k "$2" --arg v "$3"
}

# _m15p_condition JSON TYPE — l'objet a la condition TYPE à True (status.conditions ou status.parents[].conditions).
_m15p_condition() {
  _m15p_jq "$1" '[.status.conditions[]?, .status.parents[]?.conditions[]?] | any(.type == $t and .status == "True")' --arg t "$2"
}

# --- GitLab (jeton des checks, lecture) -------------------------------------------------------------

# _m15p_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m15p_contenu_main() {
  local p="${1//\//%2F}" f
  f="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main" 2>/dev/null || true
}

# _m15p_contient TEXTE REGEX… — le texte est non vide et contient chaque motif (grep -E, sans casse).
_m15p_contient() {
  local c="$1" m
  shift
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m15p_doc_main CHEMIN REGEX… — fichier de plateforme/medisphere sur main, avec chaque motif.
_m15p_doc_main() {
  local chemin="$1"
  shift
  _m15p_contient "$(_m15p_contenu_main plateforme/medisphere "$chemin")" "$@"
}

# _m15p_doc_prefixe DOSSIER PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous DOSSIER (récursif) sur main de
# plateforme/medisphere, qui contient chaque motif.
_m15p_doc_prefixe() {
  local d="${1//\//%2F}" p="$2" chemin
  shift 2
  chemin="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -r --arg p "$p" '[.[]? | select(.type == "blob" and (.name | startswith($p))) | .path][0] // ""' 2>/dev/null)" || chemin=""
  [[ -n "$chemin" ]] || return 1
  (($# == 0)) || _m15p_doc_main "$chemin" "$@"
}

# _m15p_arbre_non_vide PROJET DOSSIER — le dossier contient au moins un fichier sur main.
_m15p_arbre_non_vide() {
  local p="${1//\//%2F}" d="${2//\//%2F}"
  gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -e 'any(.[]?; .type == "blob")' >/dev/null 2>&1
}

# _m15p_recherche_main PROJET TEXTE — le texte apparaît dans un fichier de main (recherche GitLab).
_m15p_recherche_main() {
  local p="${1//\//%2F}" t
  t="$(jq -rn --arg t "$2" '$t | @uri')"
  gitlab_api "projects/$p/search?scope=blobs&ref=main&search=$t" 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1
}

# _m15p_job_reussi PROJET MOTIF — un job de main dont le nom contient MOTIF a réussi (100 derniers).
_m15p_job_reussi() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; .ref == "main" and (.name | contains($m)))' >/dev/null 2>&1
}

# _m15p_values_jq FILTRE — filtre yq (expression booléenne) sur composants/cilium/values.yaml de main
# de plateforme/k8s ; OK si le résultat est « true ».
_m15p_values_jq() {
  local v
  v="$(_m15p_contenu_main plateforme/k8s composants/cilium/values.yaml)"
  [[ -n "$v" ]] || return 1
  [[ "$(yq -r "$1" <<<"$v" 2>/dev/null)" == true ]]
}

# --- DNS, HTTPS ------------------------------------------------------------------------------------------

# _m15p_resout NOM IP [SERVEUR] — le nom résout exactement vers IP (A) sur le serveur (défaut dns01).
_m15p_resout() {
  local r
  r="$(dig +short +time=3 +tries=1 "@${3:-${_M15P_DNS[0]}}" "$1" A 2>/dev/null | tail -n 1)" || r=""
  [[ "$r" == "$2" ]]
}

# _m15p_code_https URL [OPTIONS curl…] — code HTTP (000 si pas de réponse), certificat vérifié contre la racine.
_m15p_code_https() {
  local url="$1"
  shift
  curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" --cacert "$_M15P_RACINE" "$@" "$url" 2>/dev/null || true
}

# _m15p_https_code URL REGEX [OPTIONS curl…] — le code HTTP correspond à la regex.
_m15p_https_code() {
  local url="$1" r="$2"
  shift 2
  [[ "$(_m15p_code_https "$url" "$@")" =~ $r ]]
}

# _m15p_entetes URL — en-têtes de la réponse HTTPS (HEAD), certificat vérifié.
_m15p_entetes() {
  curl -sI --max-time "${WB_TIMEOUT:-5}" --cacert "$_M15P_RACINE" "$1" 2>/dev/null || true
}

# --- Divers ----------------------------------------------------------------------------------------------

# _m15p_mode_600 FICHIER — le fichier existe, appartient à l'utilisateur courant et est en 600.
_m15p_mode_600() {
  [[ -f "$1" ]] && [[ "$(stat -c '%U:%a' "$1" 2>/dev/null)" == "$(id -un):600" ]]
}

# _m15p_version_min VERSION MINIMUM — VERSION (« 1.20.2 », « v1.20.2 ») ≥ MINIMUM (tri des versions).
_m15p_version_min() {
  local v="${1#v}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$(printf '%s\n%s\n' "$2" "$v" | sort -V | head -n 1)" == "$2" ]]
}

# _m15p_tag_image JSON CONTENEUR — étiquette de version de l'image d'un conteneur (sans l'empreinte).
_m15p_tag_image() {
  jq -r --arg c "$2" '.spec.template.spec.containers[] | select(.name == $c) | .image' <<<"$1" 2>/dev/null \
    | sed -E 's/@sha256:.*$//; s/^.*://' || true
}
