# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E12.sh — M17-E12 « Hooks, ordre de déploiement et migrations de schéma ». Lecture seule.

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E12 — Hooks, ordre de déploiement et migrations de schéma"
require_cmd jq kubectl curl

_e12_d="$(_m17d_obj mediagenda-dev deploy mediagenda)"
_e12_v="$(_m17d_version_chart "$_e12_d")" || _e12_v=""
check_cmd "release de dev : chart ${_e12_v:-?} ≥ 0.5.0" _m17d_version_ge "$_e12_v" 0.5.0
_e12_j="$(_m17d_obj mediagenda-dev job mediagenda-migrations)"
check_cmd "Job mediagenda-migrations : hook …,pre-upgrade" _m17d_jq "$_e12_j" \
  '.metadata.annotations["helm.sh/hook"] | test("pre-upgrade")'
check_cmd "Job mediagenda-migrations : politique before-hook-creation (le Job terminé est conservé)" _m17d_jq "$_e12_j" \
  '.metadata.annotations["helm.sh/hook-delete-policy"] | test("before-hook-creation")'
check_cmd "Job mediagenda-migrations : dernière exécution réussie" _m17d_jq "$_e12_j" '(.status.succeeded // 0) >= 1'
_e12_h="$_m17d_brouillons/e12/historique.txt"
_e12_echec_puis_ok() {
  awk '/[[:space:]]failed[[:space:]]/ {f=1} f && /[[:space:]](deployed|superseded)[[:space:]]/ && !/failed/ {ok=1} END {exit !ok}' "$_e12_h" 2>/dev/null
}
check_cmd "historique.txt : une révision failed suivie d'une révision réussie" _e12_echec_puis_ok
check_cmd "journal.md : image observée pendant l'échec notée" \
  _m17d_fichier_contient "$_m17d_brouillons/e12/journal.md" 'registry\.par1\.medisphere\.internal/medisphere/mediagenda-api'
check_cmd "dev : API prête" _m17d_pret "$_e12_d"
check_cmd "Harbor : charts/mediagenda:0.5.0 publié et signé" _m17d_harbor_signe mediagenda 0.5.0
