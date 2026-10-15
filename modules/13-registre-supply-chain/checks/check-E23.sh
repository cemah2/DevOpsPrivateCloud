# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts de « bash -c » entre apostrophes (arguments en $1)
# check-E23.sh — M13-E23 « Sous le capot : l'API de distribution OCI » : la note cite le digest actuel
# d'une version v* de medisphere/mediagenda-api, l'API des référents et l'effet du reformatage ; ORAS 1.3.

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E23 — L'API de distribution OCI"
require_cmd jq curl

_m13_e23_note="$(_m13p_fichier_main plateforme/medisphere docs/registre/notes/api-oci.md 2>/dev/null)" || _m13_e23_note=""
check_cmd "docs/registre/notes/api-oci.md publié sur main" test -n "$_m13_e23_note"
_m13_e23_digest_cite() {
  local l d
  l="$(_m13p_api "projects/medisphere/repositories/mediagenda-api/artifacts?with_tag=true&page_size=50")" || return 1
  for d in $(jq -r '.[]? | select(any(.tags[]?; .name | test("^v[0-9]"))) | .digest' <<<"$l"); do
    grep -qF "$d" <<<"$_m13_e23_note" && return 0
  done
  return 1
}
check_cmd "la note cite le digest d'une version v* existante de medisphere/mediagenda-api" _m13_e23_digest_cite
check_cmd "… avec le recalcul (sha256sum) et le jeton (service/token, Bearer)" \
  bash -c 'grep -q "sha256sum" <<<"$1" && grep -q "service/token" <<<"$1" && grep -qi "bearer" <<<"$1"' _ "$_m13_e23_note"
check_cmd "… l'API des référents (/referrers/, artifactType)" \
  bash -c 'grep -q "/referrers/" <<<"$1" && grep -q "artifactType" <<<"$1"' _ "$_m13_e23_note"
check_cmd "… les types de média OCI rencontrés" \
  bash -c 'grep -q "application/vnd.oci.image" <<<"$1"' _ "$_m13_e23_note"
check_output "ORAS 1.3 installé sur adm01" 'Version:[[:space:]]+1\.3\.' oras version
