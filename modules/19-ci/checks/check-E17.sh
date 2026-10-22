# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M19-E17 : Promouvoir une image par merge request
# À lancer depuis adm01. Lecture seule : API GitLab (jetons de projet, variables, branches protégées,
# MR et leurs différences). Le jeton des checks appartient à ton compte administrateur (read_api).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E17 — Promouvoir une image par merge request"
require_cmd jq curl

_m19o_e17_jetons="$(_m19o_api "$_M19O_P_DEP/access_tokens?per_page=100")"
check_cmd "mediagenda/deploiement : jeton de projet ci-promotion actif" \
  _m19o_json "$_m19o_e17_jetons" 'any(.[]; .name == "ci-promotion" and .active == true and .revoked == false)'
check_cmd "… avec une date d'expiration (≤ 1 an)" _m19o_json "$_m19o_e17_jetons" \
  'any(.[]; .name == "ci-promotion" and .active == true and .expires_at != null
       and ((.expires_at | strptime("%Y-%m-%d") | mktime) - now) < 366 * 86400)'
check_cmd "… portées api et write_repository seulement, rôle Developer" _m19o_json "$_m19o_e17_jetons" \
  'any(.[]; .name == "ci-promotion" and .active == true and (.scopes | sort) == ["api", "write_repository"] and .access_level == 30)'

_m19o_e17_c="$(_m19o_code "$_M19O_P_API/variables/DEPLOIEMENT_TOKEN")"
if [[ "$_m19o_e17_c" == 200 ]]; then
  check_cmd "mediagenda/api : DEPLOIEMENT_TOKEN protégée et masquée" \
    _m19o_json "$(_m19o_api "$_M19O_P_API/variables/DEPLOIEMENT_TOKEN")" '.protected == true and .masked == true'
elif [[ "$_m19o_e17_c" == 404 ]]; then
  check_cmd "mediagenda/api : variable DEPLOIEMENT_TOKEN présente" false
else
  skip "mediagenda/api : DEPLOIEMENT_TOKEN protégée et masquée" "API des variables refusée au jeton des checks (HTTP $_m19o_e17_c)"
fi

check_cmd "mediagenda/deploiement : main protégée, poussée interdite, fusion réservée aux Maintainers" \
  _m19o_json "$(_m19o_api "$_M19O_P_DEP/protected_branches/main")" \
  '([.push_access_levels[].access_level] | all(. == 0)) and ([.merge_access_levels[].access_level] | length >= 1 and all(. >= 40))'

# Dernière MR de promotion vers dev, ouverte ou fusionnée, et ses différences.
_m19o_e17_mr="$(_m19o_api "$_M19O_P_DEP/merge_requests?state=all&order_by=created_at&sort=desc&per_page=50" \
  | jq -c '[.[] | select(.source_branch | test("^promotion/dev-v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty' 2>/dev/null || true)"
check_cmd "mediagenda/deploiement : une MR promotion/dev-vX.Y.Z existe" test -n "$_m19o_e17_mr"
_m19o_e17_iid="$(jq -r '.iid // 0' <<<"${_m19o_e17_mr:-null}" 2>/dev/null || echo 0)"
_m19o_e17_diff="$(_m19o_api "$_M19O_P_DEP/merge_requests/$_m19o_e17_iid/diffs?per_page=100")"
check_cmd "cette MR change l'image de overlays/dev par empreinte (digest sha256)" _m19o_json "$_m19o_e17_diff" \
  'any(.[]; .new_path == "overlays/dev/kustomization.yaml" and (.diff | test("\\n\\+ *digest: *sha256:[a-f0-9]{64}")))'
check_cmd "… et la version de overlays/dev/livraison.yaml" _m19o_json "$_m19o_e17_diff" \
  'any(.[]; .new_path == "overlays/dev/livraison.yaml" and (.diff | test("\\n\\+ *version: *v[0-9]+\\.[0-9]+\\.[0-9]+")))'
check_cmd "… ouverte par le robot du jeton ci-promotion, pas par un humain" _m19o_json "$_m19o_e17_mr" \
  '(.author.username | test("^project_[0-9]+_bot")) or (.author.name == "ci-promotion")'
