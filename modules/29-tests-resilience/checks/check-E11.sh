# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # motifs entre apostrophes
#
# check-E11.sh — M29-E11 : Revue : les politiques Rego et le test k6 du stagiaire
# À lancer depuis adm01. Lecture seule : versions corrigées poussées sur les branches revue-lucas de
# plateforme/politiques (rego/revue-lucas/) et de plateforme/resilience (charge/revue-lucas/), lues par
# l'API GitLab ; opa local sur une copie temporaire. La revue elle-même (REVUE.md) s'auto-évalue avec
# le corrigé : le contrôle ne vérifie que des défauts objectivables.

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E11 — Revue : les politiques Rego et le test k6 du stagiaire"
require_cmd jq curl

_m29o_e11_b=revue-lucas
check_cmd "plateforme/politiques : branche $_m29o_e11_b" _m29o_branche_existe "$_M29D_P_POLITIQUES" "$_m29o_e11_b"
check_cmd "plateforme/resilience : branche $_m29o_e11_b" _m29o_branche_existe "$_M29D_P_RESILIENCE" "$_m29o_e11_b"

_m29o_e11_r="$(_m29d_contenu "$_M29D_P_POLITIQUES" rego/revue-lucas/REVUE.md "$_m29o_e11_b")"
check_cmd "REVUE.md : au moins 10 défauts numérotés (tableau)" bash -c '(( $(grep -Ec "^\| *[0-9]+ *\|" <<<"$1") >= 10 ))' _ "$_m29o_e11_r"

# --- Rego corrigé --------------------------------------------------------------------------------------
_m29o_e11_rego="$(_m29d_contenu "$_M29D_P_POLITIQUES" rego/revue-lucas/garde-fous.rego "$_m29o_e11_b")"
check_cmd "garde-fous.rego corrigé : paquet lu par conftest --namespace tofu" bash -c 'grep -Eq "^package tofu$" <<<"$1"' _ "$_m29o_e11_rego"
check_cmd "garde-fous.rego corrigé : Rego v1 (contains, if ; plus de « deny[msg] { »)" bash -c '
  [[ -n "$1" ]] && ! grep -Eq "^[a-z_]+\[[a-z]+\] *\{" <<<"$1" && grep -q "contains" <<<"$1"' _ "$_m29o_e11_rego"
check_cmd "garde-fous.rego corrigé : chemin change.after (plus de rc.after)" bash -c '
  grep -q "change.after" <<<"$1" && ! grep -Eq "rc\.after\." <<<"$1"' _ "$_m29o_e11_rego"
check_cmd "garde-fous.rego corrigé : plus de règle au nom ignoré par conftest (refuser_…)" bash -c '! grep -Eq "^refuser_" <<<"$1"' _ "$_m29o_e11_rego"
check_cmd "garde-fous.rego corrigé : un remplacement est une destruction (pas seulement actions[0])" bash -c '! grep -q "actions\[0\]" <<<"$1"' _ "$_m29o_e11_rego"
if command -v opa >/dev/null 2>&1 && [[ -n "$_m29o_e11_rego" ]]; then
  _m29d_copier "$_M29D_P_POLITIQUES" rego/revue-lucas "$_M29D_TMP/rl" "$_m29o_e11_b" >/dev/null
  check_cmd "opa check --strict rego/revue-lucas : compile en Rego v1" opa check --strict "$_M29D_TMP/rl/rego/revue-lucas"
  check_cmd "opa test rego/revue-lucas : les tests passent" opa test "$_M29D_TMP/rl/rego/revue-lucas"
  check_cmd "tests corrigés : au moins un cas qui DOIT être refusé (pas seulement le plan correct)" bash -c '
    cat "$1"/*_test.rego 2>/dev/null | grep -Eq "some msg in|count\(.*deny.*\) *(>|>=|==) *[1-9]"' _ "$_M29D_TMP/rl/rego/revue-lucas"
else
  skip "compilation et tests de la version corrigée" "opa absent de adm01, ou fichier absent"
fi

# --- k6 corrigé ----------------------------------------------------------------------------------------
_m29o_e11_k6="$(_m29d_contenu "$_M29D_P_RESILIENCE" charge/revue-lucas/creneaux-charge.js "$_m29o_e11_b")"
check_cmd "creneaux-charge.js corrigé : présent" bash -c '[[ -n "$1" ]]' _ "$_m29o_e11_k6"
check_cmd "k6 corrigé : plus de cible de production par défaut" bash -c '! grep -Eq "https://mediagenda\.apps\.par1" <<<"$1"' _ "$_m29o_e11_k6"
check_cmd "k6 corrigé : des seuils (thresholds), dont le taux d'échec" bash -c 'grep -q "thresholds" <<<"$1" && grep -q "http_req_failed" <<<"$1"' _ "$_m29o_e11_k6"
check_cmd "k6 corrigé : aucune donnée réelle (pas de fichier de patients, pas de NIR)" bash -c '! grep -Eiq "patients\.csv|\bnir\b|papaparse" <<<"$1"' _ "$_m29o_e11_k6"
check_cmd "k6 corrigé : vérification TLS conservée" bash -c '! grep -q "insecureSkipTLSVerify" <<<"$1"' _ "$_m29o_e11_k6"
check_cmd "k6 corrigé : la création attend 201 (plus « < 500 » qui accepte les 422)" bash -c '
  grep -Eq "=== *201" <<<"$1" && ! grep -Eq "status *< *500" <<<"$1"' _ "$_m29o_e11_k6"
check_cmd "plateforme/resilience (branche $_m29o_e11_b) : plus de fichier de patients" bash -c '[[ -z "$1" ]]' _ \
  "$(_m29d_arbre "$_M29D_P_RESILIENCE" charge "$_m29o_e11_b" | grep -i 'patients' || true)"
