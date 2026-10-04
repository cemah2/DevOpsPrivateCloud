#!/usr/bin/env bats
# Tests de bin/ms-ranger (M02-E12/E14) : noms piégeux, manifeste, garde-fous.

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  RANGER="$RACINE/bin/ms-ranger"
  SRC="$BATS_TEST_TMPDIR/source"
  DEST="$BATS_TEST_TMPDIR/archive"
  mkdir -p "$SRC/sous dossier" "$SRC/-tiret"
  # Trois vieux fichiers aux noms difficiles, un récent, un lien symbolique.
  printf 'a\n' >"$SRC/sous dossier/deux  espaces.txt"
  printf 'b\n' >"$SRC/-tiret/-rf"
  printf 'c\n' >"$SRC/ligne un"$'\n'"ligne deux.log"
  printf 'd\n' >"$SRC/récent.txt"
  ln -s "récent.txt" "$SRC/lien"
  touch -d "2025-01-15 10:00" "$SRC/sous dossier/deux  espaces.txt" "$SRC/-tiret/-rf"
  touch -d "2025-03-01 10:00" "$SRC/ligne un"$'\n'"ligne deux.log"
}

@test "range les vieux fichiers par mois, noms intacts, manifeste vérifié" {
  run -0 "$RANGER" "$SRC" "$DEST"
  [[ -f "$DEST/2025-01/sous dossier/deux  espaces.txt" ]]
  [[ -f "$DEST/2025-01/-tiret/-rf" ]]
  [[ -f "$DEST/2025-03/ligne un"$'\n'"ligne deux.log" ]]
  [[ -f "$SRC/récent.txt" ]]
  [[ -L "$SRC/lien" ]]
  cd "$DEST"
  run -0 sha256sum --check --strict MANIFESTE-*.sha256
  [[ "${#lines[@]}" -eq 3 ]]
}

@test "--dry-run ne déplace rien" {
  run -0 "$RANGER" --dry-run "$SRC" "$DEST"
  [[ ! -e "$DEST" ]]
  [[ -f "$SRC/-tiret/-rf" ]]
}

@test "un fichier déjà présent n'est jamais écrasé (code 1)" {
  mkdir -p "$DEST/2025-01/-tiret"
  echo "ne pas écraser" >"$DEST/2025-01/-tiret/-rf"
  run -1 "$RANGER" "$SRC" "$DEST"
  [[ "$(cat "$DEST/2025-01/-tiret/-rf")" = "ne pas écraser" ]]
  [[ -f "$SRC/-tiret/-rf" ]]
}

@test "DESTINATION dans SOURCE est refusée (3)" {
  run -3 "$RANGER" "$SRC" "$SRC/archive"
}

@test "usage incorrect (2)" {
  run -2 "$RANGER" "$SRC"
  run -2 "$RANGER" --age abc "$SRC" "$DEST"
}
