# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E04.sh — M13-E04 : Des caches pour les registres publics
# À lancer depuis adm01. Lecture seule : API de Harbor (wb-checks), config.toml et images locales
# de runner02 en SSH (sudo -n pour lire), GitLab en GET.

# shellcheck source=_m13-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-decouverte.sh"

title "M13-E04 — Des caches pour les registres publics"
require_cmd jq curl

_m13_reg="$(_m13d_api "registries?page_size=100")"
[[ -n "$_m13_reg" ]] || _m13_reg='[]'

# _m13_amont TYPE URL — un point d'accès de ce type vers cette URL, sain ; affiche son id.
_m13_amont_id() {
  jq -r --arg t "$1" --arg u "$2" '[.[] | select(.type == $t and (.url | rtrimstr("/")) == $u)][0].id // empty' <<<"$_m13_reg" 2>/dev/null || true
}
_m13_amont_sain() {
  jq -e --arg t "$1" --arg u "$2" '[.[] | select(.type == $t and (.url | rtrimstr("/")) == $u and .status == "healthy")] | length == 1' <<<"$_m13_reg" >/dev/null 2>&1
}

declare -A _m13_types=([dockerhub]=docker-hub [quay]=quay [ghcr]=github-ghcr [k8s]=docker-registry)
declare -A _m13_urls=([dockerhub]=https://hub.docker.com [quay]=https://quay.io [ghcr]=https://ghcr.io [k8s]=https://registry.k8s.io)

for _m13_c in dockerhub quay ghcr k8s; do
  _m13_t="${_m13_types[$_m13_c]}"; _m13_u="${_m13_urls[$_m13_c]}"
  check_cmd "point d'accès $_m13_t → $_m13_u : sain (healthy)" _m13_amont_sain "$_m13_t" "$_m13_u"
  _m13_id="$(_m13_amont_id "$_m13_t" "$_m13_u")"
  _m13_p="$(_m13d_projet "$_m13_c")"; [[ -n "$_m13_p" ]] || _m13_p='{}'
  check_cmd "projet $_m13_c : cache de ce point d'accès, public" \
    jq -e --arg id "${_m13_id:-x}" '(.registry_id | tostring) == $id and .metadata.public == "true"' <<<"$_m13_p"
  _m13_q="$(_m13d_api "projects/$_m13_c/summary")"; [[ -n "$_m13_q" ]] || _m13_q='{}'
  check_cmd "projet $_m13_c : quota de stockage défini" jq -e '(.quota.hard.storage // -1) > 0' <<<"$_m13_q"
  _m13_n() { _m13d_api "projects/$1/repositories?page_size=10" | jq -e 'length >= 1' >/dev/null 2>&1; }
  check_cmd "projet $_m13_c : au moins un dépôt en cache" _m13_n "$_m13_c"
done
_m13_debian() { _m13d_api "projects/dockerhub/repositories?page_size=100" | jq -e '[.[].name] | index("dockerhub/library/debian")' >/dev/null 2>&1; }
check_cmd "cache dockerhub : dockerhub/library/debian présent" _m13_debian

# --- runner02 ----------------------------------------------------------------------------------------
check_ssh "runner02 : image par défaut de l'exécuteur tirée de $_M13D_NOM" runner02 \
  "sudo -n grep -E '^[[:space:]]*image *= *\"$_M13D_NOM/' /etc/gitlab-runner/config.toml"
check_ssh "runner02 : allowed_images limité à $_M13D_NOM" runner02 \
  "l=\"\$(sudo -n grep -E '^[[:space:]]*allowed_images *=' /etc/gitlab-runner/config.toml)\"; [ -n \"\$l\" ] && ! grep -Eo '\"[^\"]+\"' <<<\"\$l\" | grep -v '^\"$_M13D_NOM/' | grep -q ."
check_ssh "runner02 : mode privilégié toujours interdit" runner02 \
  "! sudo -n grep -Eq '^[[:space:]]*privileged *= *true' /etc/gitlab-runner/config.toml"
check_ssh "runner02 : des images des caches sont présentes localement" runner02 \
  "sudo -n docker images --format '{{.Repository}}' | grep -Eq '^$_M13D_NOM/(dockerhub|quay|ghcr|k8s)/'"

# --- Code ----------------------------------------------------------------------------------------------
_m13_image_yml() {
  local c
  c="$(_m13d_contenu_main "$_M13D_CITPL" image.yml)"
  [[ -n "$c" ]] || return 1
  # Toute référence d'image (clé image:, name:, variables *_IMAGE:) désigne Harbor.
  ! grep -Eo '^[[:space:]]*(image|name|[A-Z_]*IMAGE)[[:space:]]*:[[:space:]]*["'"'"']?[^ "'"'"'$#][^ "'"'"']*' <<<"$c" \
    | sed -E 's/^[^:]*:[[:space:]]*["'"'"']?//' | grep -v "^$_M13D_NOM/" | grep -q .
}
check_cmd "plateforme/ci-templates (main) : image.yml ne désigne que des images de Harbor" _m13_image_yml
_m13_podman() {
  local t
  t="$(gitlab_api "$_M13D_ANSIBLE/repository/tree?path=roles/podman_hote/templates&ref=main&per_page=100" 2>/dev/null | jq -r '.[].path' 2>/dev/null)"
  local f
  for f in $t; do
    _m13d_contenu_main "$_M13D_ANSIBLE" "$f" | grep -q 'registry.mirror' && return 0
  done
  return 1
}
check_cmd "plateforme/ansible (main) : podman_hote sait déclarer des miroirs (registry.mirror)" _m13_podman
_m13_miroirs() {
  local v
  v="$(gitlab_api "$_M13D_ANSIBLE/search?scope=blobs&search=registry.par1.medisphere.internal%2Fdockerhub&ref=main" 2>/dev/null)"
  jq -e 'length >= 1' <<<"${v:-[]}" >/dev/null 2>&1
}
check_cmd "plateforme/ansible (main) : miroir docker.io → $_M13D_NOM/dockerhub déclaré" _m13_miroirs
check_cmd "docs/registre/caches.md sur main de plateforme/medisphere" _m13d_fichier_main "$_M13D_DOC" docs/registre/caches.md
