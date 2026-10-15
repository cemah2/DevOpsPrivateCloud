# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E05.sh — M17-E05 « Valeurs, schéma de valeurs et helpers » : le schéma refuse ce qu'il doit
# refuser (rendus du chart de origin/main), release de dev en 0.2.0+, Deployment non recréé.

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

title "M17-E05 — Valeurs, schéma de valeurs et helpers"
require_cmd jq kubectl helm git

_e05_s="$(_m17d_gl_fichier mediagenda/chart charts/mediagenda/values.schema.json)"
check_cmd "mediagenda/chart (main) : values.schema.json valide et qui décrit medisphere.environnement" \
  jq -e '.properties.medisphere.properties.environnement' <<<"$_e05_s"

_e05_c="$(_m17d_chart_main)" || _e05_c=""
if [[ -n "$_e05_c" ]]; then
  _e05_ok=(--set medisphere.environnement=dev)
  check_cmd "rendu témoin (environnement dev) : réussit" helm template mediagenda "$_e05_c" -n mediagenda-dev "${_e05_ok[@]}"
  check_cmd "rendu refusé : image.tag=latest" _m17d_rendu_refuse "$_e05_c" "${_e05_ok[@]}" --set image.tag=latest
  check_cmd "rendu refusé : replicaCount=deux" _m17d_rendu_refuse "$_e05_c" "${_e05_ok[@]}" --set replicaCount=deux
  check_cmd "rendu refusé : clé inconnue (cacheTTL)" _m17d_rendu_refuse "$_e05_c" "${_e05_ok[@]}" --set cacheTTL=30
  check_cmd "rendu refusé : database.password" _m17d_rendu_refuse "$_e05_c" "${_e05_ok[@]}" --set database.password=x
  check_cmd "rendu refusé : medisphere.environnement=preprod" _m17d_rendu_refuse "$_e05_c" --set medisphere.environnement=preprod
  check_cmd "rendu refusé : prod avec une seule réplique" _m17d_rendu_refuse "$_e05_c" --set medisphere.environnement=prod --set replicaCount=1
else
  skip "règles du schéma (rendus)" "clone $_m17d_chart_clone absent ou sans origin/main"
fi

_e05_d="$(_m17d_obj mediagenda-dev deploy mediagenda)"
_e05_v="$(_m17d_version_chart "$_e05_d")" || _e05_v=""
check_cmd "release de dev : chart ${_e05_v:-?} ≥ 0.2.0" _m17d_version_ge "$_e05_v" 0.2.0
check_cmd "dev : étiquettes medisphere.internal/environnement=dev et medisphere.internal/donnees-sante" _m17d_jq "$_e05_d" \
  '.metadata.labels["medisphere.internal/environnement"] == "dev" and (.metadata.labels | has("medisphere.internal/donnees-sante"))'
_e05_uid="$(jq -r '.metadata.uid // ""' <<<"$_e05_d" 2>/dev/null)" || _e05_uid=""
check_cmd "journal.md : contient l'uid actuel du Deployment (non recréé)" \
  _m17d_fichier_contient "$_m17d_brouillons/e05/journal.md" "${_e05_uid:-uid-introuvable}"
