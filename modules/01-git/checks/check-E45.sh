# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent leurs paramètres en arguments
#
# check-E45.sh — M01-E45 « Sous le capot : packfiles, maintenance et gros dépôts »
# Import de legacy-rdv dans formation/legacy-rdv avec les binaires dans LFS, clone partiel,
# graphe de commits, rapport d'analyse. Lecture seule.

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E45 — Sous le capot : packfiles, maintenance et gros dépôts"
require_cmd git jq curl

_m01_p45="projects/formation%2Flegacy-rdv"
_m01_src="${WB_SRC:-$HOME/src}"

check_cmd "GitLab : projet formation/legacy-rdv présent" _m01_api_existe "$_m01_p45"
check_cmd "formation/legacy-rdv : historique complet importé (plus de 1000 commits sur main)" \
  _m01_api_ok "$_m01_p45/repository/commits?ref_name=main&per_page=1&page=1001" 'length == 1'
check_cmd "formation/legacy-rdv : objets LFS présents" \
  _m01_api_ok "$_m01_p45?statistics=true" '.statistics.lfs_objects_size > 0'
check_cmd "formation/legacy-rdv : dépôt Git de moins de 30 Mio (binaires hors de Git)" \
  _m01_api_ok "$_m01_p45?statistics=true" '.statistics.repository_size > 0 and .statistics.repository_size < 31457280'
check_cmd "legacy-rdv local : fichiers volumineux suivis par LFS (.gitattributes)" \
  grep -Eq 'filter=lfs' "$_m01_src/legacy-rdv/.gitattributes"
check_cmd "legacy-rdv local : graphe de commits écrit (commit-graph)" bash -c '
  o=$(git -C "$1" rev-parse --git-path objects 2>/dev/null) || exit 1
  [ -f "$o/info/commit-graph" ] || [ -d "$o/info/commit-graphs" ]' _ "$_m01_src/legacy-rdv"
check_output "clone partiel legacy-rdv-partiel : filtre de blobs actif" '^blob:' \
  git -C "$_m01_src/legacy-rdv-partiel" config --get remote.origin.partialclonefilter
check_cmd "clone partiel : objets de « promesse » (promisor) déclarés" \
  bash -c 'git -C "$1" config --get remote.origin.promisor | grep -qx true' _ "$_m01_src/legacy-rdv-partiel"
_m01_e45_brut_supprime() {
  _m01_api_existe "projects/formation%2Flegacy-rdv-brut" || return 0
  # Suppression différée (projet en attente de suppression) : acceptée.
  _m01_api_ok "projects/formation%2Flegacy-rdv-brut" '.marked_for_deletion_on != null'
}
check_cmd "projet temporaire formation/legacy-rdv-brut supprimé (ou en attente de suppression)" _m01_e45_brut_supprime
_m01_rapport45="${WB_DEPOT:-$HOME/medisphere}/docs/socle/analyses/git-gros-depot.md"
check_cmd "rapport docs/socle/analyses/git-gros-depot.md présent" test -s "$_m01_rapport45"
check_cmd "rapport : mesures de taille, stratégies de clone, LFS et maintenance traitées" bash -c '
  for m in "count-objects" "blob:none" "lfs" "maintenance" "commit-graph"; do
    grep -qiF -- "$m" "$1" || exit 1
  done' _ "$_m01_rapport45"
