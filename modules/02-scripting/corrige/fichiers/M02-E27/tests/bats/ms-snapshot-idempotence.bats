#!/usr/bin/env bats
# Tests d'idempotence et de --dry-run de bin/ms-snapshot (M02-E27). Proxmox est simulé en
# mémoire par tests/bats/fake-pve.bash : aucun accès réseau, aucune VM réelle.
# pve_api (fake-pve.bash) est appelée indirectement par main :
# shellcheck disable=SC2329
# shellcheck source-path=SCRIPTDIR

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=../../bin/ms-snapshot
  source "$BATS_TEST_DIRNAME/../../bin/ms-snapshot"
  # shellcheck source=fake-pve.bash
  source "$BATS_TEST_DIRNAME/fake-pve.bash"
  fake_pve_init
  fake_vm 2027
  # Deux instantanés posés à la main dont le nom commence par le préfixe : intouchables.
  fake_snap 2027 avant-manuel
  fake_snap 2027 avant-maj-20261003
}

nb_geres() { fake_noms 2027 | grep -cE '^avant-[0-9]{8}-[0-9]{6}$' || true; }
nb_ecritures() { grep -cE "^$1 " "$FAKE_PVE/ecritures.log" || true; }

@test "dry-run : aucune requête d'écriture, plan affiché sur la sortie standard" {
  fake_snap 2027 avant-20261001-100000
  fake_snap 2027 avant-20261002-100000
  fake_snap 2027 avant-20261003-100000
  MS_HORODATAGE=20261004-090000 run --separate-stderr main --dry-run 2027
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_PVE/ecritures.log" ]
  [[ "$output" == *$'2027\tcreer avant-20261004-090000'* ]]
  [[ "$output" == *$'2027\tsupprimer avant-20261001-100000'* ]]
  [[ "$output" != *"supprimer avant-20261002"* ]]
}

@test "dry-run : le plan annoncé est exactement celui qui est appliqué" {
  fake_snap 2027 avant-20261001-100000
  fake_snap 2027 avant-20261002-100000
  MS_HORODATAGE=20261004-090000 run --separate-stderr main --dry-run --keep 2 2027
  annonce="$(cut -f2 <<<"$output" | sort)"
  MS_HORODATAGE=20261004-090000 run main --keep 2 2027
  [ "$status" -eq 0 ]
  fait="$(sed -E 's#^POST .* snapname=([^ ]+).*#creer \1#; s#^DELETE .*/snapshot/([^ ]+).*#supprimer \1#' \
    "$FAKE_PVE/ecritures.log" | sort)"
  [ "$annonce" = "$fait" ]
}

@test "idempotence : trois exécutions (fenêtre 0) laissent keep instantanés gérés, manuels intacts" {
  for h in 090000 090100 090200; do
    MS_HORODATAGE="20261004-$h" run main --fenetre 0 --keep 2 2027
    [ "$status" -eq 0 ]
  done
  [ "$(nb_geres)" -eq 2 ]
  fake_noms 2027 | grep -qx avant-manuel
  fake_noms 2027 | grep -qx avant-maj-20261003
  fake_noms 2027 | grep -qx avant-20261004-090200
}

@test "idempotence : relance dans la fenêtre, l'instantané d'avant l'intervention est réutilisé" {
  MS_HORODATAGE=20261004-090000 run main 2027
  [ "$status" -eq 0 ]
  MS_HORODATAGE=20261004-091500 run main 2027
  [ "$status" -eq 0 ]
  [ "$(nb_ecritures POST)" -eq 1 ]
  fake_noms 2027 | grep -qx avant-20261004-090000
}

@test "idempotence : relance dans la même seconde sans fenêtre, ni doublon ni erreur" {
  MS_HORODATAGE=20261004-090000 run main --fenetre 0 2027
  [ "$status" -eq 0 ]
  MS_HORODATAGE=20261004-090000 run main --fenetre 0 2027
  [ "$status" -eq 0 ]
  [ "$(nb_ecritures POST)" -eq 1 ]
}

@test "idempotence : relance après interruption entre création et purge, la purge est terminée" {
  # État laissé par une exécution interrompue : instantané créé, purge non faite (keep 2 dépassé).
  fake_snap 2027 avant-20261001-100000
  fake_snap 2027 avant-20261002-100000
  fake_snap 2027 avant-20261004-090000 "$(date +%s)"
  MS_HORODATAGE=20261004-090500 run main --keep 2 2027
  [ "$status" -eq 0 ]
  [ "$(nb_geres)" -eq 2 ]
  [ "$(nb_ecritures POST)" -eq 0 ]
  fake_noms 2027 | grep -qx avant-20261004-090000
}

@test "idempotence : VM verrouillée, aucune action et code 1" {
  echo snapshot >"$FAKE_PVE/lock-2027"
  run main 2027
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_PVE/ecritures.log" ]
}

@test "idempotence : création en échec, aucune suppression" {
  fake_snap 2027 avant-20261001-100000
  fake_snap 2027 avant-20261002-100000
  fake_snap 2027 avant-20261003-100000
  touch "$FAKE_PVE/echec-creation"
  MS_HORODATAGE=20261004-090000 run main --keep 1 2027
  [ "$status" -eq 1 ]
  [ "$(nb_ecritures DELETE)" -eq 0 ]
  [ "$(nb_geres)" -eq 3 ]
}

@test "garde-fou : VM hors du pool lab refusée avant toute action (code 3)" {
  fake_vm 104 perso
  run main 2027 104
  [ "$status" -eq 3 ]
  [ ! -s "$FAKE_PVE/ecritures.log" ]
}

@test "usage : fenêtre, keep et préfixe invalides" {
  run main --fenetre 2000 2027
  [ "$status" -eq 2 ]
  run main --keep 0 2027
  [ "$status" -eq 2 ]
  run main --prefix 'av*nt' 2027
  [ "$status" -eq 3 ]
}
