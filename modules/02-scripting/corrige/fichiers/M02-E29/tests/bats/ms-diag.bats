#!/usr/bin/env bats
# Tests de sbin/ms-diag (M02-E29, SEC-359) : le filtre des arguments, la première barrière de
# l'outil autorisé par sudo. Ils tournent SANS droits root (CI sur runner01) : ms-diag valide ses
# arguments avant de vérifier qu'il est root, et rien n'est collecté ni écrit.
# Les contre-preuves sous sudo (compte astreinte01) restent manuelles et vérifiées par
# « lab/bin/check 02 29 ».

bats_require_minimum_version 1.5.0

setup() {
  DIAG="$BATS_TEST_DIRNAME/../../sbin/ms-diag"
}

@test "--help : usage sur la sortie standard, code 0" {
  run -0 --separate-stderr "$DIAG" --help
  [[ "${lines[0]}" == Usage* ]]
  [[ -z "$stderr" ]]
}

@test "sans unité : erreur d'usage (2), aide sur la sortie d'erreur" {
  run -2 --separate-stderr "$DIAG"
  [[ -z "$output" && "$stderr" == Usage* ]]
}

@test "option inconnue ou détournée : erreur d'usage (2)" {
  run -2 "$DIAG" --output=/etc/passwd ssh.service
  run -2 "$DIAG" -o /tmp/x ssh.service
}

@test "--depuis hors de 1 à 72, ou sans valeur : erreur d'usage (2)" {
  run -2 "$DIAG" --depuis 0 ssh.service
  run -2 "$DIAG" --depuis 73 ssh.service
  run -2 "$DIAG" --depuis '2;id' ssh.service
  run -2 "$DIAG" --depuis
}

@test "noms d'unité hostiles refusés (2) : chemin, remontée, commande, espace, sans suffixe" {
  local a
  # shellcheck disable=SC2016  # « $(id) » est volontairement littéral : le nom hostile à refuser
  for a in /etc/shadow ../../etc/shadow 'ssh.service;id' 'ssh.service id' '$(id).service' ssh; do
    run -2 --separate-stderr "$DIAG" "$a"
    [[ -z "$output" ]]
  done
}

@test "plus de cinq unités : erreur d'usage (2)" {
  run -2 "$DIAG" a.service b.service c.service d.service e.service f.service
}

@test "arguments valides sans être root : refus (3), rien sur la sortie standard" {
  if ((EUID == 0)); then
    skip "test sans objet en root"
  fi
  run -3 --separate-stderr "$DIAG" --depuis 4 ssh.service gitlab-runner.service
  [[ -z "$output" && "$stderr" == *"sudo"* ]]
}
