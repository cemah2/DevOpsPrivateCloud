# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E07.sh — M17-E07 « Tester un chart ». Lecture seule (helm unittest sur une copie temporaire).

# shellcheck source=_m17-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-operationnel.sh"

title "M17-E07 — Tester un chart"
require_cmd jq kubectl helm git

check_cmd "mediagenda/chart (main) : au moins cinq suites tests/*_test.yaml" \
  _m17o_compte_fichiers mediagenda/chart charts/mediagenda/tests '_test\.yaml$' 5
_e07_t="$(_m17d_gl_arbre mediagenda/chart charts/mediagenda/templates/tests | head -n 1)" || _e07_t=""
_e07_test_helm() {
  local c
  [[ -n "$_e07_t" ]] || return 1
  c="$(_m17d_gl_fichier mediagenda/chart "$_e07_t")"
  grep -Eq 'helm\.sh/hook"?:[[:space:]]*"?test' <<<"$c" && ! grep -Eq 'image:[[:space:]]*"?(busybox|curlimages|docker\.io)' <<<"$c"
}
check_cmd "templates/tests/ : un test « helm test » sans image publique" _e07_test_helm
check_cmd "mediagenda/chart (main) : ct.yaml" _m17d_gl_existe mediagenda/chart ct.yaml
check_cmd "mediagenda/chart (main) : au moins un ci/*-values.yaml" \
  _m17o_compte_fichiers mediagenda/chart charts/mediagenda/ci '-values\.yaml$' 1
if helm plugin list 2>/dev/null | grep -q '^unittest'; then
  _e07_c="$(_m17d_chart_main)" || _e07_c=""
  if [[ -n "$_e07_c" ]]; then
    check_cmd "helm unittest du chart de origin/main : tout passe" helm unittest "$_e07_c"
  else
    skip "helm unittest" "clone $_m17d_chart_clone absent ou sans origin/main"
  fi
else
  skip "helm unittest" "plugin helm-unittest non installé sur adm01"
fi
check_cmd "dev : le pod de test mediagenda-test-pret a réussi" _m17d_jq "$(_m17d_obj mediagenda-dev pod mediagenda-test-pret)" \
  '.status.phase == "Succeeded"'
check_cmd "l'espace jetable wb-ct a été supprimé" _m17o_espace_absent wb-ct
check_cmd "aucun PersistentVolume ne reste lié à wb-ct" _m17o_aucun_pv_de wb-ct
