# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes
#
# check-E21.sh — M15-E21 : Revue : politiques et routes du stagiaire
# À lancer depuis adm01. Lecture seule : fichiers de ~/m15/e21/ (revue.md et corrige/).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E21 — Revue : politiques et routes du stagiaire"
require_cmd yq

_m15o_d="$_M15O_TRAVAIL/e21"
_m15o_c="$_m15o_d/corrige"
# Tous les fichiers corrigés en un flux YAML (un « --- » entre deux fichiers : sans lui, deux
# documents sans en-tête fusionneraient).
_m15o_tous() {
  local f
  for f in "$_m15o_c"/*.yaml; do [[ -f "$f" ]] && { cat "$f"; printf '\n---\n'; }; done
  return 0
}

# --- Revue ---------------------------------------------------------------------------------------------
_m15o_n="$(grep -ciE '(bloquant|majeur|mineur)' "$_m15o_d/revue.md" 2>/dev/null || true)"
check_cmd "revue.md : au moins 12 défauts qualifiés (bloquant/majeur/mineur ; trouvés : ${_m15o_n:-0})" \
  bash -c '(( ${1:-0} >= 12 ))' _ "${_m15o_n:-0}"
check_cmd "revue.md : la réponse à Lucas est rédigée" grep -qsi 'lucas' "$_m15o_d/revue.md"

# --- Fichiers corrigés -------------------------------------------------------------------------------
check_cmd "corrige/ contient la version corrigée des fichiers de Lucas" \
  bash -c 'ls "$1"/*.yaml >/dev/null 2>&1' _ "$_m15o_c"
check_cmd "fichiers corrigés lisibles en YAML" bash -c 'for f in "$1"/*.yaml; do yq "." "$f" >/dev/null || exit 1; done' _ "$_m15o_c"
_m15o_j="$(_m15o_tous | yq ea -o json -I0 '[. | select(. != null)]' 2>/dev/null || echo '[]')"
_m15o_t="$(_m15o_tous)"
check_cmd "espace : plus de PSA privileged" _m15o_jq "$_m15o_j" \
  'all(.[]; (.metadata.labels["pod-security.kubernetes.io/enforce"] // "") != "privileged")'
check_cmd "plus aucune Gateway propre à MédiDoc ni demande de 10.10.41.10" _m15o_jq "$_m15o_j" \
  'length > 0 and ([.[] | select(.kind == "Gateway")] | length == 0) and ([.. | strings | select(. == "10.10.41.10")] | length == 0)'
check_cmd "plus aucun ReferenceGrant vers des Secrets" _m15o_jq "$_m15o_j" \
  '[.[] | select(.kind == "ReferenceGrant") | .spec.to[]? | select(.kind == "Secret")] | length == 0'
check_cmd "la route vise gw-par1 (passerelles) et le port 8080 du Service" _m15o_jq "$_m15o_j" \
  '[.[] | select(.kind == "HTTPRoute")] as $r | ($r | length) > 0 and all($r[]; .spec.parentRefs[0].name == "gw-par1" and .spec.parentRefs[0].namespace == "passerelles" and all(.spec.rules[].backendRefs[]; .port == 8080))'
check_cmd "politiques : aucune autorisation ouverte (règle vide, 0.0.0.0/0, toFQDNs « * », world/cluster)" \
  _m15o_politiques_lucas "$_m15o_j"
check_cmd "aucun Secret en clair dans les fichiers corrigés" bash -c \
  '[[ "$(jq "[.[] | select(.kind == \"Secret\")] | length" <<<"$1")" == 0 ]] && ! grep -q "AWS_SECRET_ACCESS_KEY" <<<"$2"' _ "$_m15o_j" "$_m15o_t"
