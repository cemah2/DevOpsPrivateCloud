# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
#
# check-E05.sh — M29-E05 : k6 : premier test de charge de MédiAgenda
# À lancer depuis adm01. Lecture seule : scripts de plateforme/resilience (main) recopiés dans un
# dossier temporaire et lus par « k6 inspect » (aucune requête n'est envoyée) ; Prometheus du cluster
# (requêtes de recette des 7 derniers jours) ; liste des rendez-vous de recette (GET).

# shellcheck source=_m29-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-decouverte.sh"

title "M29-E05 — k6 : premier test de charge de MédiAgenda"
require_cmd jq curl

check_cmd "k6 1.8 sur adm01" _m29d_version_outil k6 '^k6 v1\.8\.'

_m29d_e05_s="$(_m29d_contenu "$_M29D_P_RESILIENCE" charge/premier-test.js)"
check_cmd "$_M29D_P_RESILIENCE : charge/premier-test.js sur main" bash -c '[[ -n "$1" ]]' _ "$_m29d_e05_s"
_m29d_e05_tout="$_m29d_e05_s
$(for f in $(_m29d_arbre "$_M29D_P_RESILIENCE" charge/lib); do _m29d_contenu "$_M29D_P_RESILIENCE" "$f"; done)"

check_cmd "seuils (thresholds) : latence p(95)<250 et taux d'échec (http_req_failed)" bash -c '
  grep -q "thresholds" <<<"$1" && grep -Eq "p\(95\) *< *250" <<<"$1" && grep -q "http_req_failed" <<<"$1"' _ "$_m29d_e05_s"
check_cmd "deux modèles de charge : VUs (fermé) et taux d'arrivée constant (ouvert)" bash -c '
  grep -q "constant-arrival-rate" <<<"$1" && grep -Eq "constant-vus|ramping-vus|\bvus *:" <<<"$1"' _ "$_m29d_e05_s"
check_cmd "réservation ET annulation (POST puis DELETE) : la base de recette reste propre" bash -c '
  grep -q "http.post" <<<"$1" && grep -Eq "http\.del\(|http\.request\(.DELETE" <<<"$1"' _ "$_m29d_e05_tout"
check_cmd "noms de requêtes regroupés (tags name : pas une série par identifiant)" bash -c 'grep -Eq "name: *.[A-Z]+ /api/v1/rendez-vous/\{id\}" <<<"$1"' _ "$_m29d_e05_tout"
check_cmd "garde-fou : la production n'est jamais une cible (aucune URL https://mediagenda.apps…, liste d'autorisation)" bash -c '
  ! grep -Eq "https://mediagenda\.apps\.par1" <<<"$1" && grep -q "mediagenda-recette" <<<"$1"' _ "$_m29d_e05_tout"
check_cmd "dates avec fuseau (sinon 422 masqués) et données factices (pas de NIR, pas de fichier de patients)" bash -c '
  grep -Eq "\+0[12]:00|Z\b" <<<"$1" && ! grep -Eiq "\bnir\b|patients\.csv|open\(" <<<"$1"' _ "$_m29d_e05_tout"
check_cmd "vérification TLS conservée (pas d'insecureSkipTLSVerify)" bash -c '! grep -q "insecureSkipTLSVerify" <<<"$1"' _ "$_m29d_e05_tout"

# --- k6 lit le script (aucune requête envoyée) ------------------------------------------------------
if command -v k6 >/dev/null 2>&1 && [[ -n "$_m29d_e05_s" ]]; then
  _m29d_copier "$_M29D_P_RESILIENCE" charge "$_M29D_TMP/r" >/dev/null
  _m29d_e05_insp="$(cd "$_M29D_TMP/r" && k6 inspect charge/premier-test.js 2>/dev/null || true)"
  check_cmd "k6 inspect charge/premier-test.js : le script se charge, ses seuils sont lus" \
    _m29d_json "$_m29d_e05_insp" '.thresholds | length >= 2'
  _m29d_e05_prod="$(cd "$_M29D_TMP/r" && k6 inspect -e BASE_URL=https://mediagenda.apps.par1.medisphere.internal charge/premier-test.js 2>&1 || true)"
  check_cmd "k6 inspect avec BASE_URL=production : le script REFUSE de se charger" \
    bash -c '! jq -e ".scenarios" <<<"$1" >/dev/null 2>&1' _ "$_m29d_e05_prod"
else
  skip "k6 inspect du script" "k6 absent de adm01 ou script absent"
fi

# --- Traces du test dans la recette ---------------------------------------------------------------------
_m29d_e05_post="$(_m29d_prom_valeur 'sum(increase(mediagenda_http_requests_total{namespace="mediagenda-recette", methode="POST", route="/api/v1/rendez-vous"}[7d]))')"
check_cmd "la recette a reçu au moins 100 réservations ces 7 derniers jours (test lancé) : ${_m29d_e05_post%%.*}" \
  _m29d_superieur "$_m29d_e05_post" 99
_m29d_e05_liste="$(curl -sf --max-time "$WB_TIMEOUT" "$_M29D_RECETTE/api/v1/rendez-vous?limite=1000" 2>/dev/null || true)"
if [[ -n "$_m29d_e05_liste" ]]; then
  check_cmd "aucun rendez-vous factice resté dans la base de recette (praticiens dr-k6-*)" _m29d_json "$_m29d_e05_liste" \
    '[.[] | select(.praticien | startswith("dr-k6-"))] | length == 0'
else
  skip "rendez-vous factices restés en base" "API de recette injoignable depuis adm01"
fi
