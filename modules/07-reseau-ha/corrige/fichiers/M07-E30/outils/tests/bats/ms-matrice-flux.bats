#!/usr/bin/env bats
# Tests de ms-matrice-flux (M07-E30).

setup() {
  GEN="$BATS_TEST_DIRNAME/../../bin/ms-matrice-flux"
  M="$BATS_TEST_DIRNAME/donnees/matrice-essai.yml"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "génère un tableau par chaîne, motifs et références compris" {
  run "$GEN" "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| 1 | \$WAN |  |  | 10.10.70.200 | tcp 80, 443 | publié | M07-E13 |"* ]]
  [[ "$output" == *"## Vers les passerelles (chaîne input)"* ]]
  [[ "$output" == *"| postrouting |"* ]]
}

@test "--verifier : 0 si à jour, 1 sinon" {
  "$GEN" -o "$TMP/doc.md" "$M"
  run "$GEN" --verifier "$TMP/doc.md" "$M"
  [ "$status" -eq 0 ]
  echo "ajout à la main" >>"$TMP/doc.md"
  run "$GEN" --verifier "$TMP/doc.md" "$M"
  [ "$status" -eq 1 ]
}

@test "un flux sans motif est refusé" {
  printf 'pare_feu_entree:\n  - {proto: tcp, ports: 22}\n' >"$TMP/m.yml"
  run "$GEN" "$TMP/m.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"motif"* ]]
}

@test "usage incorrect : code 2" {
  run "$GEN"
  [ "$status" -eq 2 ]
}
