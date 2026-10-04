#!/usr/bin/env bats
# Tests de bin/ms-export-config (M02-E13/E14) : publication atomique, rotation,
# nettoyage après échec, exclusion mutuelle. API simulée (helpers/bin/curl).

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  preparer_faux_pve
  EXPORT="$RACINE/bin/ms-export-config"
  export MS_EXPORT_DIR="$BATS_TEST_TMPDIR/exports"
}

@test "un export complet est publié et « dernier » pointe dessus" {
  run -0 "$EXPORT"
  [[ -L "$MS_EXPORT_DIR/dernier" ]]
  d="$MS_EXPORT_DIR/$(readlink "$MS_EXPORT_DIR/dernier")"
  [[ -d "$d" ]]
  # 8 VMs du pool lab dans les fixtures (template compris), plus l'index.
  [[ "$(find "$d" -name '*.json' ! -name index.json | wc -l)" -eq 8 ]]
  [[ -f "$d/2020-m02-cobaye.json" ]]
  jq -e 'length == 8' "$d/index.json"
  [[ ! -e "$d/2029-m02-horspool.json" ]]
}

@test "aucun dossier temporaire ne reste après succès" {
  run -0 "$EXPORT"
  [[ -z "$(find "$MS_EXPORT_DIR" -maxdepth 1 -name '.*' ! -name . -print -quit)" ]]
}

@test "échec en cours d'export : rien n'est publié, rien ne traîne" {
  run -0 "$EXPORT"
  avant="$(readlink "$MS_EXPORT_DIR/dernier")"
  sleep 1 # horodatage différent
  touch "$FAUX_PVE_ETAT/config-ko-2020"
  run -1 "$EXPORT"
  [[ "$(readlink "$MS_EXPORT_DIR/dernier")" = "$avant" ]]
  [[ "$(find "$MS_EXPORT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]]
  [[ "$output" == *"dossier temporaire supprimé"* ]]
}

@test "la rotation ne garde que N exports et ignore les autres dossiers" {
  mkdir -p "$MS_EXPORT_DIR/20250101-000000" "$MS_EXPORT_DIR/20250102-000000" \
    "$MS_EXPORT_DIR/20250103-000000" "$MS_EXPORT_DIR/a-garder"
  run -0 "$EXPORT" --garder 2
  [[ -d "$MS_EXPORT_DIR/a-garder" ]]
  [[ ! -e "$MS_EXPORT_DIR/20250101-000000" ]]
  [[ ! -e "$MS_EXPORT_DIR/20250102-000000" ]]
  [[ -d "$MS_EXPORT_DIR/20250103-000000" ]]
}

@test "une seconde exécution simultanée est refusée (3) sans rien écrire" {
  mkdir -p "$MS_LOCK_DIR"
  flock "$MS_LOCK_DIR/ms-export-config.lock" sleep 30 3>&- &
  local pid=$!
  sleep 0.3
  run -3 "$EXPORT"
  [[ ! -e "$MS_EXPORT_DIR/dernier" ]]
  pkill -P "$pid" || true
  kill "$pid" || true
}
