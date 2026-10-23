# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E03.sh — M29-E03 : conftest et Rego v1 : des règles sur les plans OpenTofu
# À lancer depuis adm01. Lecture seule : fichiers de plateforme/politiques (main) recopiés dans un
# dossier temporaire, puis opa test et conftest LOCAUX sur des plans témoins (contrat de l'énoncé :
# paquet tofu, data.contexte.etat, data.contexte.etiquettes_mr, étiquette destruction-autorisee).

# shellcheck source=_m29-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-decouverte.sh"

title "M29-E03 — conftest et Rego v1 : des règles sur les plans OpenTofu"
require_cmd jq curl

check_cmd "OPA 1.21 sur adm01" _m29d_version_outil opa '^Version: 1\.21\.'
check_cmd "conftest 0.71 sur adm01" _m29d_version_outil conftest '^Conftest: 0\.71\.'

# --- 1. Les fichiers ---------------------------------------------------------------------------------
_m29d_e03_d="$_M29D_TMP/politiques"
_m29d_e03_n="$(_m29d_copier "$_M29D_P_POLITIQUES" rego "$_m29d_e03_d")"
_m29d_e03_regles="$(find "$_m29d_e03_d/rego/tofu" -name '*.rego' ! -name '*_test.rego' 2>/dev/null | wc -l)"
_m29d_e03_tests="$(find "$_m29d_e03_d/rego/tofu" -name '*_test.rego' 2>/dev/null | wc -l)"
check_cmd "plateforme/politiques : rego/tofu/ contient des règles (${_m29d_e03_regles}) et des tests (${_m29d_e03_tests}) — ${_m29d_e03_n:-0} fichiers lus" \
  bash -c '(( $1 >= 1 && $2 >= 1 ))' _ "$_m29d_e03_regles" "$_m29d_e03_tests"
check_cmd "plateforme/politiques : rego/donnees/plages-vmid.yaml" test -s "$_m29d_e03_d/rego/donnees/plages-vmid.yaml"
check_cmd "règles de rego/tofu dans le paquet « tofu » (celui que conftest lit avec --namespace tofu)" bash -c '
  for f in $(find "$1/rego/tofu" -name "*.rego" ! -name "*_test.rego"); do
    grep -Eq "^package tofu$" "$f" || exit 1
  done' _ "$_m29d_e03_d"
check_cmd "syntaxe Rego v1 (pas de « deny[msg] { » : contains et if)" bash -c '
  ! grep -rEq "^(deny|warn|violation)[A-Za-z_]*\[" "$1/rego/tofu" && grep -rq "contains msg if" "$1/rego/tofu"' _ "$_m29d_e03_d"
_m29d_e03_ntests="$(cat "$_m29d_e03_d"/rego/tofu/*_test.rego 2>/dev/null | grep -cE "^test_[A-Za-z0-9_]+ if" || true)"
check_cmd "au moins 8 tests unitaires (${_m29d_e03_ntests})" bash -c '(( ${1:-0} >= 8 ))' _ "$_m29d_e03_ntests"

if ! command -v opa >/dev/null 2>&1 || ! command -v conftest >/dev/null 2>&1; then
  skip "exécution des tests et des politiques" "opa ou conftest absent de adm01"
else
  # --- 2. Les tests passent avec OPA 1.21 --------------------------------------------------------------
  check_cmd "opa test rego/tofu rego/donnees : tous les tests passent" opa test "$_m29d_e03_d/rego/tofu" "$_m29d_e03_d/rego/donnees"

  # --- 3. Comportement sur des plans témoins (format de tofu show -json) --------------------------------
  _m29d_e03_vm() { # ADRESSE ACTIONS AVANT APRÈS
    jq -nc --arg a "$1" --argjson ac "$2" --argjson av "$3" --argjson ap "$4" \
      '{format_version: "1.2", resource_changes: [{address: $a, mode: "managed", type: "proxmox_virtual_environment_vm", name: "vm",
        change: {actions: $ac, before: $av, after: $ap}}]}'
  }
  _m29d_e03_vm 'module.a.proxmox_virtual_environment_vm.vm' '["create"]' null \
    '{"name":"m29-a","vm_id":2291,"pool_id":"lab","tags":["env-m29"]}' >"$_M29D_TMP/conforme.json"
  _m29d_e03_vm 'module.a.proxmox_virtual_environment_vm.vm' '["create"]' null \
    '{"name":"m29-a","vm_id":5001,"pool_id":"lab","tags":["env-m29"]}' >"$_M29D_TMP/vmid.json"
  _m29d_e03_vm 'module.a.proxmox_virtual_environment_vm.vm' '["create"]' null \
    '{"name":"m29-a","vm_id":2291,"pool_id":null,"tags":["env-m29"]}' >"$_M29D_TMP/pool.json"
  _m29d_e03_vm 'module.a.proxmox_virtual_environment_vm.vm' '["create"]' null \
    '{"name":"m29-a","vm_id":2291,"pool_id":"lab","tags":["env-m28"]}' >"$_M29D_TMP/etiquette.json"
  _m29d_e03_vm 'module.dns02.proxmox_virtual_environment_vm.vm' '["create","delete"]' \
    '{"name":"dns02","vm_id":1008,"pool_id":"lab","tags":["role-dns","socle"]}' \
    '{"name":"dns02","vm_id":1008,"pool_id":"lab","tags":["role-dns","socle"]}' >"$_M29D_TMP/remplacement.json"
  printf '{"contexte":{"etat":"envs/m29","etiquettes_mr":[]}}' >"$_M29D_TMP/ctx-m29.json"
  printf '{"contexte":{"etat":"socle","etiquettes_mr":[]}}' >"$_M29D_TMP/ctx-socle.json"
  printf '{"contexte":{"etat":"socle","etiquettes_mr":["destruction-autorisee"]}}' >"$_M29D_TMP/ctx-socle-ok.json"

  _m29d_e03_conftest() { # PLAN CONTEXTE — code de sortie de conftest
    conftest test --no-color --namespace tofu -p "$_m29d_e03_d/rego/tofu" --data "$_m29d_e03_d/rego/donnees" \
      --data "$_M29D_TMP/$2" "$_M29D_TMP/$1" >/dev/null 2>&1
  }
  _m29d_e03_refuse() { ! _m29d_e03_conftest "$@"; }
  check_cmd "plan conforme (VMID 2291, pool lab, env-m29) : accepté" _m29d_e03_conftest conforme.json ctx-m29.json
  check_cmd "VMID 5001 dans envs/m29 : refusé" _m29d_e03_refuse vmid.json ctx-m29.json
  check_cmd "pool absent : refusé" _m29d_e03_refuse pool.json ctx-m29.json
  check_cmd "étiquette env-m28 dans envs/m29 : refusée" _m29d_e03_refuse etiquette.json ctx-m29.json
  check_cmd "remplacement d'une VM du socle (create_before_destroy) sans étiquette de MR : refusé" \
    _m29d_e03_refuse remplacement.json ctx-socle.json
  check_cmd "même remplacement avec l'étiquette de MR destruction-autorisee : accepté" \
    _m29d_e03_conftest remplacement.json ctx-socle-ok.json
  check_cmd "plan sans contexte : refusé (pas de silence quand une donnée manque)" bash -c '
    ! conftest test --no-color --namespace tofu -p "$1/rego/tofu" --data "$1/rego/donnees" "$2" >/dev/null 2>&1' \
    _ "$_m29d_e03_d" "$_M29D_TMP/conforme.json"
fi
