# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E11.sh — M17-E11 « Revue : le chart du stagiaire » : contrôle de la version corrigée déposée
# dans ~/m17/e11/medidoc (rendu local, rien n'est installé). La revue elle-même est auto-évaluée.

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E11 — Revue : le chart du stagiaire"
require_cmd helm yq jq

_e11_c="$_m17d_brouillons/e11/medidoc"
_e11_lignes() {
  local n
  n="$(grep -Ec '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$_m17d_brouillons/e11/revue.md" 2>/dev/null)" || n=0
  (( n >= 12 ))
}
check_cmd "revue.md : au moins 12 défauts numérotés dans le tableau" _e11_lignes
check_cmd "version corrigée : helm lint --strict" helm lint --strict "$_e11_c"
_e11_r="$(helm template medidoc "$_e11_c" -n medidoc-dev 2>/dev/null)" || _e11_r=""
check_cmd "version corrigée : se rend avec les valeurs par défaut" test -n "$_e11_r"
_e11_valeurs() { ! grep -Eq 'AKIA|wJalrXUtnFEMI|secretKey:[[:space:]]*[^[:space:]"]' "$_e11_c/values.yaml" 2>/dev/null; }
check_cmd "values.yaml : plus de clé S3" _e11_valeurs
if [[ -z "$_e11_r" ]]; then
  check_cmd "contrôles du rendu (images, Ingress, espaces, secrets, sélecteurs, sécurité, sondes)" false
else
  _e11_j="$(yq -o json -I0 '.' <<<"$_e11_r" 2>/dev/null | jq -s 'map(select(. != null))' 2>/dev/null)" || _e11_j="[]"
  check_cmd "rendu : aucune image en latest ni hors du registre MédiSphère" _m17d_jq "$_e11_j" \
    '[.[] | .. | objects | select(has("image")) | .image | strings] | length > 0 and all(test("^registry\\.par1\\.medisphere\\.internal/") and (test(":latest$") | not))'
  check_cmd "rendu : aucun Ingress" _m17d_jq "$_e11_j" '[.[] | select(.kind == "Ingress")] | length == 0'
  check_cmd "rendu : aucun espace de noms codé en dur" _m17d_jq "$_e11_j" '[.[] | select(.metadata.namespace?)] | length == 0'
  check_cmd "rendu : aucune clé S3 en clair (Secret, ConfigMap)" _m17d_jq "$_e11_j" \
    '[.[] | select(.kind == "Secret" or .kind == "ConfigMap") | (.data // {}) + (.stringData // {}) | keys[] | select(test("AWS_(SECRET|ACCESS)"))] | length == 0'
  check_cmd "rendu : sélecteurs sans version ni chart" _m17d_jq "$_e11_j" \
    '[.[] | select(.kind == "Deployment") | .spec.selector.matchLabels | keys[] | select(. == "app.kubernetes.io/version" or . == "helm.sh/chart")] | length == 0'
  _e11_d="$(jq -c '[.[] | select(.kind == "Deployment")][0] // empty' <<<"$_e11_j" 2>/dev/null)" || _e11_d=""
  check_cmd "rendu : pods conformes à restricted" _m17d_restricted "$_e11_d"
  check_cmd "rendu : vivacité sur /healthz (pas /readyz)" _m17d_jq "$_e11_d" \
    '[.spec.template.spec.containers[] | .livenessProbe.httpGet.path] | all(. == "/healthz")'
fi
