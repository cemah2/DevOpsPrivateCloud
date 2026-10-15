# shellcheck shell=bash
# _m18-production.sh — fonctions partagées par les checks M18-E13 à M18-E25 (paliers 3 à 5), lecture seule.
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh). Préfixe _m18p_.
#
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute affectation par $(…)
# qui peut échouer est suivie de « || … ».
#
# Accès (exception documentée du module, énoncé du palier 3) : les clusters d'essai n'ont pas de compte
# wb-checks. Les contrôles lisent avec les kubeconfig de ~/.config/workbook/m18/ et talosctl, et ne lancent
# QUE des commandes de lecture (get, describe, version, config info). SSH vers les nœuds avec « sudo -n »
# pour des lectures seulement (stat, grep, ps, sysctl -n, « k3s secrets-encrypt status »). Aucune valeur
# de Secret n'est affichée ni conservée.
#
# Variables de lab/lab.env utilisées (toutes facultatives) :
#   WB_M18_DIR            dossier des fichiers d'accès (défaut ~/.config/workbook/m18)
#   WB_M18_RECETTE_URL    URL de /sante du cluster de recette éphémère (M18-E18)
#   WB_PVE_HOST, WB_S3_ENDPOINT, WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE, WB_TIMEOUT, WB_OS_CLOUD_PLATEFORME

_M18P_DIR="${WB_M18_DIR:-$HOME/.config/workbook/m18}"
_M18P_KC_GESTION="$_M18P_DIR/k3s01.kubeconfig"
_M18P_KC_CAPI="$_M18P_DIR/capi-essai.kubeconfig"
_M18P_KC_RKE2="$_M18P_DIR/rke2.kubeconfig"
_M18P_KC_TALOS="$_M18P_DIR/talos.kubeconfig"
_M18P_KC_K3SHA="$_M18P_DIR/k3s-ha.kubeconfig"
_M18P_KC_RECETTE="$_M18P_DIR/recette-mediagenda.kubeconfig"
_M18P_TALOSCONFIG="$_M18P_DIR/talosconfig"
_M18P_TALOS_CP=10.10.99.85
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
_M18P_TALOS_TRAV=(10.10.99.86 10.10.99.87)
# shellcheck disable=SC2034
_M18P_RKE2=(rke2-01 rke2-02 rke2-03)
_M18P_ESPACE_CAPI=capi-essai
_M18P_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M18P_S3_ENV="$HOME/.config/workbook/s3-etcd-m18.env"
# shellcheck disable=SC2034
_M18P_COMPARTIMENT=etcd-m18
# shellcheck disable=SC2034
_M18P_PROJET=plateforme/distributions
# shellcheck disable=SC2034
_M18P_DOCS=docs/kubernetes/distributions

# --- Kubernetes (kubeconfig des clusters d'essai, lecture seule) -------------------------------

# _m18p_k KUBECONFIG ARGS… — kubectl en lecture sur un cluster d'essai.
_m18p_k() {
  local kc="$1"; shift
  [[ -r "$kc" ]] || return 1
  kubectl --kubeconfig "$kc" --request-timeout="${WB_TIMEOUT:-5}s" "$@" 2>/dev/null
}

# _m18p_json KUBECONFIG ARGS… — sortie JSON valide de « kubectl ARGS -o json », ou « null ».
_m18p_json() {
  local s
  s="$(_m18p_k "$@" -o json)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m18p_jq JSON FILTRE — 0 si le filtre jq est vrai sur JSON (faux si JSON vaut null).
_m18p_jq() { [[ "$1" != null && -n "$1" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# _m18p_joignable KUBECONFIG — l'API répond « ok » à /readyz.
_m18p_joignable() { [[ "$(_m18p_k "$1" get --raw /readyz)" == ok ]]; }

# _m18p_noeuds_prets KUBECONFIG [MIN] — au moins MIN nœuds (défaut 1), tous Ready.
_m18p_noeuds_prets() {
  local n
  n="$(_m18p_json "$1" get nodes)"
  _m18p_jq "$n" "(.items | length) >= ${2:-1} and all(.items[]; any(.status.conditions[]; .type == \"Ready\" and .status == \"True\"))"
}

# _m18p_g ARGS… — kubectl en lecture sur le cluster de gestion (k3s01).
_m18p_g() { _m18p_k "$_M18P_KC_GESTION" "$@"; }

# _m18p_gjson ARGS… — JSON depuis le cluster de gestion.
_m18p_gjson() { _m18p_json "$_M18P_KC_GESTION" "$@"; }

# _m18p_temoin KUBECONFIG — valeur du témoin de restauration (wb-essais/temoin-restauration, clé etat).
_m18p_temoin() { _m18p_k "$1" -n wb-essais get configmap temoin-restauration -o jsonpath='{.data.etat}'; }

# --- Talos ----------------------------------------------------------------------------------

# _m18p_talos ARGS… — talosctl en lecture avec le talosconfig d'administration.
_m18p_talos() {
  [[ -r "$_M18P_TALOSCONFIG" ]] || return 1
  timeout "$(( ${WB_TIMEOUT:-5} * 3 ))" talosctl --talosconfig "$_M18P_TALOSCONFIG" "$@" 2>/dev/null
}

# _m18p_talos_roles FICHIER — rôles (Organisation du certificat client) du contexte courant d'un talosconfig.
_m18p_talos_roles() {
  local f="$1" ctx crt
  [[ -r "$f" ]] || return 1
  ctx="$(yq -r '.context' "$f" 2>/dev/null)" || return 1
  crt="$(yq -r ".contexts[\"$ctx\"].crt" "$f" 2>/dev/null)" || return 1
  base64 -d <<<"$crt" 2>/dev/null | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | sed -n 's/^ *organizationName *= *//p'
}

# --- Nœuds (SSH, lectures) --------------------------------------------------------------------

# _m18p_sudo HÔTE COMMANDE — commande de LECTURE en root sur un nœud (sudo -n).
_m18p_sudo() { remote "$1" "sudo -n $2" 2>/dev/null; }

# _m18p_pve COMMANDE — commande de LECTURE sur l'hyperviseur.
_m18p_pve() { remote "$WB_PVE_HOST" "$1" 2>/dev/null; }

# _m18p_tags VMID — étiquettes Proxmox de la VM ou du template (une par ligne).
_m18p_tags() { _m18p_pve "qm config $1" | sed -n 's/^tags: //p' | tr -s ';,' '\n' | sed '/^$/d'; }

# _m18p_a_tag VMID ÉTIQUETTE — 0 si la VM porte l'étiquette.
_m18p_a_tag() { _m18p_tags "$1" | grep -qx -- "$2"; }

# --- Stockage objet (identité etcd-m18, liste et lecture) ------------------------------------

_m18p_s3() {
  [[ -r "$_M18P_S3_ENV" ]] || return 1
  (
    set -a
    # shellcheck source=/dev/null
    . "$_M18P_S3_ENV"
    set +a
    exec aws --endpoint-url "$_M18P_S3" --output json "$@" </dev/null
  )
}

# _m18p_s3_dernier PRÉFIXE — « clé<TAB>date » de l'objet le plus récent sous PRÉFIXE (vide si aucun).
_m18p_s3_dernier() {
  local l
  l="$(_m18p_s3 s3api list-objects-v2 --bucket etcd-m18 --prefix "$1" 2>/dev/null)" || l=""
  jq -r '[.Contents[]?] | sort_by(.LastModified) | last | select(. != null) | "\(.Key)\t\(.LastModified)"' <<<"${l:-null}" 2>/dev/null
}

# _m18p_s3_age_s PRÉFIXE — âge en secondes de l'objet le plus récent sous PRÉFIXE.
_m18p_s3_age_s() {
  local d
  d="$(_m18p_s3_dernier "$1" | cut -f2)" || d=""
  [[ -n "$d" ]] || return 1
  echo $(( $(date +%s) - $(date -d "$d" +%s) ))
}

# _m18p_s3_recent PRÉFIXE SECONDES — 0 si l'objet le plus récent sous PRÉFIXE a moins de SECONDES.
_m18p_s3_recent() {
  local a
  a="$(_m18p_s3_age_s "$1")" || return 1
  [[ "$a" =~ ^[0-9]+$ ]] && (( a < $2 ))
}

# _m18p_s3_chiffre CLÉ — 0 si l'objet commence par l'en-tête age (age-encryption.org/v1).
_m18p_s3_chiffre() {
  local t
  t="$(mktemp)"
  _m18p_s3 s3api get-object --bucket etcd-m18 --key "$1" --range bytes=0-20 "$t" >/dev/null 2>&1 || { rm -f "$t"; return 1; }
  if head -c 21 "$t" | grep -q '^age-encryption\.org/v1'; then rm -f "$t"; return 0; fi
  rm -f "$t"; return 1
}

# --- GitLab (jeton des checks, lecture) -------------------------------------------------------

_m18p_enc() { jq -rn --arg s "$1" '$s | @uri'; }

# _m18p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main (vide si absent).
_m18p_fichier_main() {
  gitlab_api "projects/$(_m18p_enc "$1")/repository/files/$(_m18p_enc "$2")/raw?ref=main" 2>/dev/null
}

# _m18p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif.
_m18p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m18p_fichier_main "$p" "$chemin")" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m18p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m18p_arbre() {
  gitlab_api "projects/$(_m18p_enc "$1")/repository/tree?ref=main&path=$(_m18p_enc "$2")&recursive=true&per_page=100" 2>/dev/null \
    | jq -r '.[]? | select(.type == "blob") | .path' 2>/dev/null
}

# _m18p_un_fichier_contient PROJET DOSSIER REGEX… — au moins un fichier YAML/MD/SH sous DOSSIER contient
# chaque motif (sur main). Limité à 40 fichiers lus.
_m18p_un_fichier_contient() {
  local p="$1" d="$2" f
  shift 2
  while read -r f; do
    [[ -n "$f" ]] || continue
    if _m18p_fichier_contient "$p" "$f" "$@"; then return 0; fi
  done < <(_m18p_arbre "$p" "$d" | grep -E '\.(ya?ml|md|sh|json|env|j2)$' | head -40)
  return 1
}

# _m18p_doc_prefixe DOSSIER PRÉFIXE REGEX… — un fichier « PRÉFIXE* » sous DOSSIER de plateforme/medisphere
# (main) contient chaque motif.
_m18p_doc_prefixe() {
  local d="$1" pre="$2" f
  shift 2
  f="$(_m18p_arbre plateforme/medisphere "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -1)" || f=""
  [[ -n "$f" ]] || return 1
  _m18p_fichier_contient plateforme/medisphere "$f" "$@"
}

# --- Fichiers locaux -----------------------------------------------------------------------------

# _m18p_local600 FICHIER — le fichier existe, appartient à l'utilisateur et est en 600.
_m18p_local600() { [[ -r "$1" && "$(stat -c '%a %U' "$1")" == "600 $(id -un)" ]]; }

# _m18p_cluster_disponible — le Cluster capi-essai est « Available » (condition v1beta2) vu de k3s01.
_m18p_cluster_disponible() {
  local c
  c="$(_m18p_gjson get clusters.v1beta2.cluster.x-k8s.io capi-essai -n "$_M18P_ESPACE_CAPI")"
  _m18p_jq "$c" 'any(.status.conditions[]?; .type == "Available" and .status == "True")'
}
