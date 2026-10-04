#!/usr/bin/env bats
# Tests de bin/ms-etat-hotes (M02-E28). Un faux ssh (tests/bats/fake-bin/ssh) remplace le vrai :
# aucun accès réseau, durée de chaque connexion maîtrisée (FAKE_SSH_DELAI).

setup() {
  export PATH="$BATS_TEST_DIRNAME/fake-bin:$PATH"
  export FAKE_SSH_JOURNAL="$BATS_TEST_TMPDIR/ssh.log"
  export FAKE_SSH_DELAI=1
  OUTIL="$BATS_TEST_DIRNAME/../../bin/ms-etat-hotes"
}

@test "parallèle : sortie dans l'ordre des arguments, quel que soit l'ordre d'arrivée" {
  run "$OUTIL" -j 4 h1 h2 h3 h4 h5 h6
  [[ "$status" -eq 0 ]]
  [[ "$(cut -f1 <<<"$output" | tr '\n' ' ')" = "h1 h2 h3 h4 h5 h6 " ]]
  [[ "$(cut -f2 <<<"$output" | sort -u)" = "ok" ]]
}

@test "parallèle : 8 hôtes d'une seconde avec -j 8 prennent nettement moins de 8 s" {
  debut="$SECONDS"
  run "$OUTIL" -j 8 h1 h2 h3 h4 h5 h6 h7 h8
  [[ "$status" -eq 0 ]]
  [[ $((SECONDS - debut)) -lt 4 ]]
}

@test "parallèle : -j borne le nombre de connexions simultanées" {
  export FAKE_SSH_DELAI=1
  debut="$SECONDS"
  run "$OUTIL" -j 2 h1 h2 h3 h4
  [[ "$status" -eq 0 ]]
  # 4 hôtes, 2 à la fois, 1 s chacun : au moins 2 s
  [[ $((SECONDS - debut)) -ge 2 ]]
}

@test "parallèle : un hôte injoignable (ssh 255) n'empêche pas d'interroger les suivants" {
  run "$OUTIL" -j 2 h1 injoignable-1 h2 erreur-1 h3
  [[ "$status" -eq 1 ]]
  [[ "$(grep -c . "$FAKE_SSH_JOURNAL")" -eq 5 ]]
  [[ "$(sed -n 2p <<<"$output")" == injoignable-1$'\t'injoignable* ]]
  [[ "$(sed -n 4p <<<"$output")" == erreur-1$'\t'erreur* ]]
  [[ "$(sed -n 5p <<<"$output")" == h3$'\t'ok* ]]
}

@test "parallèle : aucun fichier temporaire ne reste après l'exécution" {
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  run "$OUTIL" -j 2 h1 h2
  [[ "$status" -eq 0 ]]
  [[ -z "$(ls -A "$TMPDIR")" ]]
}

@test "usage : sans hôte ou avec -j invalide, code 2" {
  run "$OUTIL"
  [[ "$status" -eq 2 ]]
  run "$OUTIL" -j 0 h1
  [[ "$status" -eq 2 ]]
  run "$OUTIL" -j beaucoup h1
  [[ "$status" -eq 2 ]]
}
