#!/usr/bin/env bats
# Tests de bin/ms-verif-socle (M02-E34). Les fonctions d'accès au réseau (ssh, dig, openssl) sont
# remplacées par des fonctions de test : aucun accès réseau.
# Fonctions de remplacement appelées indirectement par main :
# shellcheck disable=SC2329
# shellcheck source-path=SCRIPTDIR

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=../../bin/ms-verif-socle
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-socle"
  # Les outils réseau peuvent manquer sur le runner : ils ne sont pas appelés dans ces tests.
  require_cmd() { :; }
  ip_alias() { case "$1" in gw01) echo 10.10.10.1 ;; git01) echo 10.10.20.12 ;; *) echo "" ;; esac; }
  resoudre_a() { case "$1" in gw01.*) echo 10.10.10.1 ;; git01.*) echo 10.10.20.12 ;; esac; }
  resoudre_ptr() { case "$1" in 10.10.10.1) echo gw01.par1.medisphere.internal. ;; 10.10.20.12) echo git01.par1.medisphere.internal. ;; esac; }
  executer_distant() {
    [[ "$1" == gw01 || "$1" == git01 ]] || return 255
    printf '%s\n' "Reference ID    : 0A0A0A01 (10.10.10.1)" "Stratum         : 3" \
      "System time     : 0.000021000 seconds fast of NTP time" "Leap status     : Normal" "@@disque ${DISQUE:-42}"
  }
  port_ouvert() { [[ "$1" == 10.10.20.12 ]]; }
  tester_tls() { [[ "${TLS_OK:-1}" == 1 ]]; }
}

@test "socle sain : code 0, cinq contrôles par hôte" {
  run main gw01 git01
  [ "$status" -eq 0 ]
  [ "$(grep -c $'^gw01\t' <<<"$output")" -eq 5 ]
  [[ "$output" == *$'gw01\ttls\tNA'* ]]
  [[ "$output" == *$'git01\ttls\tOK'* ]]
}

@test "hôte inconnu : KO mais les autres hôtes sont contrôlés" {
  run main hote-inexistant gw01
  [ "$status" -eq 1 ]
  [[ "$output" == *$'hote-inexistant\tdns\tKO'* ]]
  [[ "$output" == *$'hote-inexistant\tssh\tKO'* ]]
  [[ "$output" == *$'gw01\tssh\tOK'* ]]
}

@test "disque plein : KO" {
  DISQUE=91 run main gw01
  [ "$status" -eq 1 ]
  [[ "$output" == *$'gw01\tdisque\tKO'* ]]
}

@test "certificat expirant : KO" {
  TLS_OK=0 run main git01
  [ "$status" -eq 1 ]
  [[ "$output" == *$'git01\ttls\tKO'* ]]
}

@test "--json : tableau JSON valide" {
  run --separate-stderr main --json gw01
  [ "$status" -eq 0 ]
  jq -e 'type == "array" and length == 5 and all(.[]; has("hote") and has("controle") and has("etat"))' <<<"$output"
}

@test "usage : option inconnue ou nom invalide, code 2" {
  run main --nimporte
  [ "$status" -eq 2 ]
  run main 'gw01;id'
  [ "$status" -eq 2 ]
}
