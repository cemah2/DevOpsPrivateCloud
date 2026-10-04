# shellcheck shell=bash
# check-E44.sh — M02-E44 « Sous le capot : expansions, sous-shells et descripteurs ».
# Livrables dans le clone de plateforme/outils : l'analyse rédigée et la spécification
# exécutable (tests bats), versionnées. Les tests bats sont rejoués (ils n'écrivent que dans
# leur dossier temporaire). Lecture seule.

title "M02-E44 — Sous le capot : expansions, sous-shells et descripteurs"
require_cmd git

_m02_e44_outils="${WB_SRC:-$HOME/src}/outils"
_m02_e44_doc="$_m02_e44_outils/docs/analyses/sous-le-capot-bash.md"
_m02_e44_bats="$_m02_e44_outils/tests/bats/sous-le-capot.bats"

_m02_e44_reponses() {
  # Section des réponses, avec au moins 10 entrées numérotées (« 1. », « **1.** » ou « ### 1 »).
  awk '/^## Réponses aux questions/ {s = 1; next} /^## / {s = 0} s' "$_m02_e44_doc" 2>/dev/null \
    | grep -cE '^(\*\*)?(#+ *)?(Q ?)?([1-9]|1[0-9])[.)]' | { read -r n; ((n >= 10)); }
}

_m02_e44_nb_tests() { [[ "$(grep -cE '^@test ' "$_m02_e44_bats" 2>/dev/null)" -ge 10 ]]; }

_m02_e44_versionne() {
  (cd "$_m02_e44_outils" \
    && git ls-files --error-unmatch docs/analyses/sous-le-capot-bash.md tests/bats/sous-le-capot.bats >/dev/null 2>&1)
}

check_cmd "analyse docs/analyses/sous-le-capot-bash.md présente" test -s "$_m02_e44_doc"
check_cmd "analyse : section « ## Réponses aux questions » avec au moins 10 réponses numérotées" _m02_e44_reponses
check_cmd "spécification exécutable tests/bats/sous-le-capot.bats : au moins 10 tests" _m02_e44_nb_tests
if command -v bats >/dev/null 2>&1; then
  check_cmd "spécification exécutable : tous les tests passent" timeout 120 bats "$_m02_e44_bats"
else
  skip "spécification exécutable : exécution" "bats absent de ce poste"
fi
check_cmd "les deux livrables sont versionnés dans plateforme/outils" _m02_e44_versionne
