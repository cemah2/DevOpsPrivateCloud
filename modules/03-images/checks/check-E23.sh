# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # arguments évalués par bash -c
#
# check-E23.sh — M03-E23 « Sous le capot : mesurer un premier démarrage »
# Le rapport de mesure existe, contient les mesures et les analyses demandées, et la VM de
# mesure a été détruite.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E23 — Sous le capot : mesurer un premier démarrage"
require_cmd jq ssh git
_m03_charger
_m03_rap="$_M03_DOC/mesures/premier-demarrage.md"

check_cmd "rapport docs/socle/mesures/premier-demarrage.md présent" test -s "$_m03_rap"
check_cmd "rapport commité dans ~/medisphere" \
  bash -c 'git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1 && [ -z "$(git -C "$1" status --porcelain -- "$2")" ]' \
  _ "${WB_DEPOT:-$HOME/medisphere}" "docs/socle/mesures/premier-demarrage.md"
check_cmd "mesures systemd (systemd-analyze : time, blame ou critical-chain)" \
  _m03_doc_contient "$_m03_rap" 'systemd-analyze' '(critical-chain|blame)'
check_cmd "mesures cloud-init (cloud-init analyze)" _m03_doc_contient "$_m03_rap" 'cloud-init analyze'
check_cmd "chronologie de bout en bout (démarrage, agent, SSH, cloud-init terminé)" \
  _m03_doc_contient "$_m03_rap" 'agent' 'ssh' '(done|termin)'
check_cmd "comparaisons demandées : second démarrage et mise à jour des paquets (ciupgrade)" \
  _m03_doc_contient "$_m03_rap" '(second|deuxi[eè]me) d[ée]marrage' 'ciupgrade'
check_cmd "durées chiffrées (au moins 10 valeurs en secondes ou ms)" \
  bash -c '[ "$(grep -Eo "[0-9]+([.,][0-9]+)? ?(s|ms|min)\b" "$1" | wc -l)" -ge 10 ]' _ "$_m03_rap"
_m03_absente() { ! _m03_existe "$1"; }
check_cmd "VM de mesure 2034 détruite" _m03_absente 2034
