# shellcheck shell=bash
# _m16-production.sh — fonctions partagées par les checks M16-E24 à M16-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Accès utilisés : kubectl en lecture avec le compte wb-checks (fonction kube, WB_K8S_KUBECONFIG ;
# pas de Secrets), SSH en lecture sur les travailleurs et sur l'hôte _admin de Ceph (WB_CEPH_ADMIN,
# commandes rbd en lecture : ls, info, image-meta list), API GitLab (jeton des checks), API publiée
# de MédiAgenda (GET seulement).

_M16P_CEPH="${WB_CEPH_ADMIN:-ceph01}"
_M16P_POOL=k8s-rbd
_M16P_API="${WB_M16_API_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
_M16P_RECETTE=mediagenda-recette
_M16P_BASE=mediagenda-db

# --- Kubernetes ----------------------------------------------------------------------------------

# _m16p_kj ARGS… — sortie JSON de « kube get ARGS -o json », ou « null » si la lecture échoue.
_m16p_kj() {
  local s
  s="$(kube get "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m16p_jq JSON FILTRE [ARGS jq…] — filtre booléen jq sur un document (faux si « null »).
_m16p_jq() {
  local j="$1" f="$2"
  shift 2
  [[ "$j" != null ]] && jq -e "$@" "$f" >/dev/null 2>&1 <<<"$j"
}

# _m16p_cluster_sain ESPACE NOM — Cluster CloudNativePG sain, toutes ses instances prêtes.
_m16p_cluster_sain() {
  _m16p_jq "$(_m16p_kj clusters.postgresql.cnpg.io "$2" -n "$1")" \
    '.status.phase == "Cluster in healthy state" and ((.status.readyInstances // 0) == .spec.instances)'
}

# _m16p_archivage_actif ESPACE NOM — condition ContinuousArchiving à True.
_m16p_archivage_actif() {
  _m16p_jq "$(_m16p_kj clusters.postgresql.cnpg.io "$2" -n "$1")" \
    'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")'
}

# _m16p_charges_pretes ESPACE — au moins un Deployment ou StatefulSet, et tous disponibles/prêts.
_m16p_charges_pretes() {
  local d s
  d="$(_m16p_kj deployments -n "$1")"
  s="$(_m16p_kj statefulsets -n "$1")"
  [[ "$d" != null && "$s" != null ]] || return 1
  jq -e -n --argjson d "$d" --argjson s "$s" '
    (($d.items | length) + ($s.items | length)) > 0
    and all($d.items[]; (.status.availableReplicas // 0) >= (.spec.replicas // 1))
    and all($s.items[]; (.status.readyReplicas // 0) >= (.spec.replicas // 1))' >/dev/null
}

# _m16p_pvc_tous_lies ESPACE — au moins un PVC, tous Bound.
_m16p_pvc_tous_lies() {
  _m16p_jq "$(_m16p_kj persistentvolumeclaims -n "$1")" '(.items | length) > 0 and all(.items[]; .status.phase == "Bound")'
}

# _m16p_image_pv PV — nom de l'image RBD d'un PV ceph-csi (volumeAttributes.imageName).
_m16p_image_pv() {
  kube get pv "$1" -o jsonpath='{.spec.csi.volumeAttributes.imageName}' 2>/dev/null
}

# _m16p_noeud_pv PV — nœud où le PV est attaché (VolumeAttachment).
_m16p_noeud_pv() {
  _m16p_kj volumeattachments | jq -r --arg p "$1" \
    '[.items[]? | select(.spec.source.persistentVolumeName == $p and (.status.attached // false)) | .spec.nodeName][0] // empty'
}

# _m16p_aucune_panne_active — aucune panne ou injection M16 marquée par lab/bin/break.
_m16p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'M16-E*' 2>/dev/null)" ]]
}

# --- Ceph (hôte _admin, sudo, lecture) ------------------------------------------------------------

# _m16p_rbd "ARGUMENTS" — rbd sur l'hôte _admin (binaire de l'hôte, sinon cephadm shell).
_m16p_rbd() {
  remote "$_M16P_CEPH" "if command -v rbd >/dev/null 2>&1; then sudo -n rbd $1; else sudo -n cephadm shell -- rbd $1; fi" 2>/dev/null
}

# _m16p_image_chiffree IMAGE — l'image porte l'état « encrypted » et une DEK (ceph-csi 3.18).
_m16p_image_chiffree() {
  local m
  m="$(_m16p_rbd "image-meta list $_M16P_POOL/$1 --format json")" || return 1
  jq -e '.["rbd.csi.ceph.com/encrypted"] == "encrypted" and ((.["rbd.csi.ceph.com/dek"] // "") | length > 0)' \
    >/dev/null 2>&1 <<<"$m"
}

# _m16p_image_absente IMAGE — l'image n'est plus dans le pool (échoue si Ceph ne répond pas).
_m16p_image_absente() {
  local l
  l="$(_m16p_rbd "ls $_M16P_POOL --format json")" || return 1
  jq -e --arg i "$1" 'index($i) | not' >/dev/null 2>&1 <<<"$l"
}

# _m16p_crypt_sur NŒUD — au moins un périphérique dm-crypt sur le nœud (volume LUKS ouvert).
_m16p_crypt_sur() {
  remote "$1" "lsblk -nr -o TYPE" 2>/dev/null | grep -qx crypt
}

# --- GitLab (jeton des checks, lecture) -------------------------------------------------------------

_m16p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m16p_doc_main CHEMIN REGEX… — fichier sur main de plateforme/medisphere, contenant chaque motif.
_m16p_doc_main() {
  local c m chemin="$1"
  shift
  c="$(_m16p_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m16p_doc_prefixe DOSSIER PRÉFIXE [REGEX…] — un fichier « PRÉFIXE* » sous DOSSIER (récursif) sur
# main de plateforme/medisphere, contenant chaque motif.
_m16p_doc_prefixe() {
  local d="${1//\//%2F}" p="$2" chemin m c
  shift 2
  chemin="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -r --arg p "$p" '[.[]? | select(.type == "blob" and (.name | startswith($p))) | .path][0] // empty')" || return 1
  [[ -n "$chemin" ]] || return 1
  (($# == 0)) && return 0
  c="$(_m16p_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m16p_recherche_main PROJET TEXTE — le texte apparaît dans un fichier de main (recherche GitLab).
_m16p_recherche_main() {
  local p="${1//\//%2F}" t
  t="$(jq -rn --arg t "$2" '$t | @uri')"
  gitlab_api "projects/$p/search?scope=blobs&ref=main&search=$t" 2>/dev/null | jq -e 'length > 0' >/dev/null
}

# _m16p_pipeline_ok PROJET — dernier pipeline de main réussi (« manual » : jobs manuels non lancés).
_m16p_pipeline_ok() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}

# --- API publiée de MédiAgenda (GET seulement) --------------------------------------------------------

# _m16p_api CHEMIN — corps de la réponse (échoue si code ≠ 200).
_m16p_api() {
  curl -sf --max-time "${WB_TIMEOUT:-5}" "$_M16P_API$1"
}

# _m16p_api_code CHEMIN — code HTTP.
_m16p_api_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" "$_M16P_API$1" 2>/dev/null || true
}
