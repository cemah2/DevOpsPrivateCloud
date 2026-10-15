# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E13.sh — M14-E13 : Comptes de service et jetons liés
# À lancer depuis adm01. Lecture seule (« kube » : comptes, pods, liaisons ; wb-checks ne lit pas
# les Secrets : l'absence de jetons permanents se vérifie à la main, étape 6).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E13 — Comptes de service et jetons liés"
require_cmd jq kubectl

for _m14o_e13_ns in mediagenda-dev mediagenda-recette; do
  _m14o_e13_sa="$(_m14o_k get serviceaccounts -n "$_m14o_e13_ns" -o json)"
  check_cmd "$_m14o_e13_ns : le compte « default » ne monte pas de jeton" \
    _m14o_json "$_m14o_e13_sa" 'any(.items[]; .metadata.name == "default" and .automountServiceAccountToken == false)'
  check_cmd "$_m14o_e13_ns : compte mediagenda-api présent, sans jeton monté" \
    _m14o_json "$_m14o_e13_sa" 'any(.items[]; .metadata.name == "mediagenda-api" and .automountServiceAccountToken == false)'
  check_cmd "$_m14o_e13_ns : aucun pod ne monte de jeton d'API (volume kube-api-access-*)" \
    _m14o_json "$(_m14o_k get pods -n "$_m14o_e13_ns" -o json)" \
    '[.items[] | select(any(.spec.volumes[]?; .name | startswith("kube-api-access-")))] | length == 0'
done
_m14o_e13_liaisons="$(jq -s '[.[].items[]]' <(_m14o_k get rolebindings -A -o json) <(_m14o_k get clusterrolebindings -o json) 2>/dev/null || true)"
check_cmd "mediagenda-api n'est lié à aucun rôle (l'API ne parle pas à Kubernetes)" \
  _m14o_json "$_m14o_e13_liaisons" '[.[] | .subjects[]? | select(.kind == "ServiceAccount" and .name == "mediagenda-api")] | length == 0'

_m14o_e13_pod="$(_m14o_k get pod jeton-projete -n wb-essais -o json)"
check_cmd "wb-essais : pod jeton-projete en marche" _m14o_json "$_m14o_e13_pod" '.status.phase == "Running"'
check_cmd "jeton-projete : jeton projeté d'audience medisphere-essai, 600 s" _m14o_json "$_m14o_e13_pod" \
  'any(.spec.volumes[]?.projected.sources[]?; .serviceAccountToken.audience == "medisphere-essai"
     and (.serviceAccountToken.expirationSeconds // 3600) == 600)'
check_cmd "jeton-projete : aucun autre jeton monté (pas de kube-api-access-*)" _m14o_json "$_m14o_e13_pod" \
  '[.spec.volumes[]? | select(.name | startswith("kube-api-access-"))] | length == 0'
check_output "journal ~/m14/e13/journal.md (jetons décodés, règle d'équipe)" '"?aud"?' cat "$_M14O_TRAVAIL/e13/journal.md"
check_cmd "le journal ne contient pas de jeton complet (trois parties signées)" \
  bash -c '! grep -Eq "eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}" "$1"' _ "$_M14O_TRAVAIL/e13/journal.md"
