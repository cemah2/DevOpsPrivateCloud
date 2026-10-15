# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2088  # « ~ » développé sur l'hôte distant ou simple libellé ; gabarits Go et chemins distants entre apostrophes
#
# check-E12.sh — M12-E12 : Images multi-architectures avec Buildx
# À lancer depuis adm01. Lecture seule : /proc/sys/fs/binfmt_misc et docker buildx inspect sur ctr01,
# lecture des archives OCI de ~/m12/e12 (sans extraction), API GitLab en GET.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E12 — Images multi-architectures avec Buildx"
require_cmd jq

# --- 1. L'émulation, par le rôle -------------------------------------------------------------------------
_m12o_e12_binfmt="$(_m12o_ssh "$_M12O_CTR01" 'cat /proc/sys/fs/binfmt_misc/qemu-aarch64')"
check_cmd "ctr01 : émulation aarch64 enregistrée et active" _m12o_correspond "$_m12o_e12_binfmt" '^enabled'
check_cmd "ctr01 : drapeau F (interpréteur utilisable depuis les conteneurs)" _m12o_correspond "$_m12o_e12_binfmt" '^flags: .*F'
check_ssh "ctr01 : paquet qemu-user-binfmt installé" "$_M12O_CTR01" "dpkg-query -W -f='\${Status}' qemu-user-binfmt | grep -q 'install ok installed'"
_m12o_e12_role() {
  local f
  f="$(gitlab_api "projects/plateforme%2Fansible/repository/tree?ref=main&recursive=true&per_page=100&path=roles/docker_engine/tasks" 2>/dev/null | jq -r '.[].path' 2>/dev/null)" || return 1
  [[ -n "$f" ]] || return 1
  local x
  for x in $f; do
    _m12o_fichier plateforme/ansible "$x" | grep -q 'qemu-user-binfmt' && return 0
  done
  return 1
}
check_cmd "plateforme/ansible (main) : le rôle docker_engine installe qemu-user-binfmt" _m12o_e12_role

# --- 2. Le constructeur --------------------------------------------------------------------------------------
_m12o_e12_builder="$(_m12o_docker 'buildx inspect multiarch')"
check_cmd "ctr01 : constructeur multiarch, pilote docker-container" _m12o_correspond "$_m12o_e12_builder" 'Driver: +docker-container'

# --- 3. Les archives -------------------------------------------------------------------------------------------
for _m12o_e12_a in medidoc-1.0.0 mediagenda-api-0.2.0; do
  _m12o_e12_p="$(_m12o_oci_plateformes "$_M12O_CTR01" "~/m12/e12/$_m12o_e12_a.oci.tar")"
  check_cmd "ctr01 : ~/m12/e12/$_m12o_e12_a.oci.tar contient linux/amd64 et linux/arm64" \
    bash -c 'grep -qx "linux/amd64" <<<"$1" && grep -qx "linux/arm64" <<<"$1"' _ "$_m12o_e12_p"
done

# --- 4. Le Dockerfile de MédiDoc --------------------------------------------------------------------------------
_m12o_e12_df="$(_m12o_fichier medidoc/medidoc Dockerfile)"
check_cmd "medidoc/medidoc (main) : étape de compilation sur \$BUILDPLATFORM" _m12o_correspond "$_m12o_e12_df" '^FROM +--platform=\$\{?BUILDPLATFORM\}?'
check_cmd "medidoc/medidoc (main) : GOARCH tiré de TARGETARCH" \
  bash -c 'grep -Eq "^ARG .*TARGETARCH" <<<"$1" && grep -Eq "GOARCH=\\\$\{?TARGETARCH" <<<"$1"' _ "$_m12o_e12_df"
