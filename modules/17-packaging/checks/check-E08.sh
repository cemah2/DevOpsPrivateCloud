# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E08.sh — M17-E08 « Publier le chart en OCI dans Harbor et le signer ». Lecture seule
# (API Harbor par le robot de lecture des checks, GitLab, journal local).

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E08 — Publier le chart en OCI dans Harbor et le signer"
require_cmd jq yq curl

_e08_p="$(harbor_api "projects/charts" 2>/dev/null)" || _e08_p=""
check_cmd "Harbor : projet charts présent et privé" _m17d_jq "$_e08_p" '.name == "charts" and (.metadata.public // "false") == "false"'
_e08_imm() {
  harbor_api "projects/charts/immutabletagrules" 2>/dev/null | jq -e '[.[] | select(.disabled != true)] | length > 0' >/dev/null 2>&1
}
check_cmd "Harbor : au moins une règle d'immuabilité active sur charts" _e08_imm
check_cmd "Harbor : charts/mediagenda:0.4.0 publié et signé" _m17d_harbor_signe mediagenda 0.4.0
check_cmd "Harbor : charts/valkey:0.12.0 recopié et signé" _m17d_harbor_signe valkey 0.12.0
_e08_robot() {
  local r
  r="$(harbor_api "robots?q=name%3D~charts%2Bci&page_size=100" 2>/dev/null)" || return 1
  jq -e '[.[] | select(.name | test("charts\\+ci$")) | select((.expires_at // -1) != -1) | select(.disable != true)] | length > 0' >/dev/null 2>&1 <<<"$r"
}
if harbor_api "robots?q=name%3D~charts%2Bci&page_size=1" >/dev/null 2>&1; then
  check_cmd "Harbor : robot charts+ci actif, avec une expiration" _e08_robot
else
  skip "robot charts+ci" "liste des robots non lisible par le compte des checks : contrôle-le dans l'interface"
fi
check_cmd "Chart.yaml (main) : valkey depuis oci://registry.par1.medisphere.internal/charts" \
  _m17o_dependance valkey repository=oci://registry.par1.medisphere.internal/charts
check_cmd "plateforme/medisphere (main) : docs/kubernetes/packaging/registre-charts.md" \
  _m17d_gl_existe plateforme/medisphere docs/kubernetes/packaging/registre-charts.md
check_cmd "journal.md : refus de republication noté (immuabilité)" \
  _m17d_fichier_contient "$_m17d_brouillons/e08/journal.md" '[Ii]mmu(table|able)'
