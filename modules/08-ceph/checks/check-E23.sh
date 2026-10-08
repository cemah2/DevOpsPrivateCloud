# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E23.sh — M08-E23 : Le cluster décrit par le code
# À lancer depuis adm01. Lecture seule : API GitLab (jeton des checks), orch ls, auth get.

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E23 — Le cluster décrit par le code"
require_cmd jq curl yq

_m08o_p="$_M08O_PROJET_CEPH"
check_cmd "projet plateforme/ceph : branche main protégée" gitlab_api "$_m08o_p/protected_branches/main"

_m08o_specs=(hosts mon mgr osd mds rgw ingress nfs)
_m08o_tout=""
for _m08o_f in "${_m08o_specs[@]}"; do
  check_cmd "specs/$_m08o_f.yaml sur main" _m08o_fichier_main "$_m08o_p" "specs/$_m08o_f.yaml"
  _m08o_tout+="$(_m08o_contenu_main "$_m08o_p" "specs/$_m08o_f.yaml")"$'\n---\n'
done
check_output "aucune clé privée dans specs/ (main)" '^0$' bash -c 'grep -c "PRIVATE KEY" <<<"$1" || true' _ "$_m08o_tout"

# Services du dépôt (type.id, ou type seul) contre services du cluster (types gérés seulement).
_m08o_noms_depot="$(yq eval-all -o=json -I=0 'select(. != null and .service_type != "host")' - <<<"$_m08o_tout" 2>/dev/null \
  | jq -r 'if .service_id then .service_type + "." + .service_id else .service_type end' 2>/dev/null | sort -u || true)"
_m08o_noms_cluster="$(_m08o_ceph orch ls --format json | jq -r '.[].service_name
  | select(test("^(mon|mgr|osd|mds|rgw|ingress|nfs)($|\\.)"))' 2>/dev/null | sort -u || true)"
_m08o_manquants="$(comm -23 <(printf '%s\n' "$_m08o_noms_cluster") <(printf '%s\n' "$_m08o_noms_depot") | tr '\n' ' ' | sed 's/ *$//')"
check_output "chaque service mon/mgr/osd/mds/rgw/ingress/nfs a sa spécification (sans : ${_m08o_manquants:-aucun})" \
  '^$' echo "$_m08o_manquants"
check_output "le cluster porte des services (lecture de orch ls)" '[a-z]' echo "$_m08o_noms_cluster"

check_cmd "README.md sur main" _m08o_fichier_main "$_m08o_p" README.md
check_cmd ".gitlab-ci.yml sur main" _m08o_fichier_main "$_m08o_p" .gitlab-ci.yml
_m08o_pipeline_ok() { gitlab_api "$_m08o_p/pipelines?ref=main&per_page=1" | jq -e '.[0].status == "success"' >/dev/null 2>&1; }
check_cmd "dernier pipeline de main réussi" _m08o_pipeline_ok
_m08o_planif() {
  local id
  for id in $(gitlab_api "$_m08o_p/pipeline_schedules?scope=active" 2>/dev/null | jq -r '.[].id' 2>/dev/null); do
    gitlab_api "$_m08o_p/pipeline_schedules/$id" | jq -e '.active == true and .last_pipeline != null' >/dev/null 2>&1 && return 0
  done
  return 1
}
check_cmd "une planification active (dérive) a déjà lancé un pipeline" _m08o_planif

_m08o_ci="$(_m08o_ceph auth get client.ci-lecture --format json)"
if jq -e 'length == 1' <<<"$_m08o_ci" >/dev/null 2>&1; then
  check_cmd "client.ci-lecture : lecture seule (aucun « w », aucun « * », aucun droit OSD)" \
    jq -e '.[0].caps | ([.[]] | all(test("allow [^ ,]*[w*]") | not)) and (has("osd") | not)' <<<"$_m08o_ci"
else
  skip "droits de la clé de dérive" "pas de client.ci-lecture : la dérive ne tourne pas avec une clé du cluster"
fi
