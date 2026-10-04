#!/usr/bin/env bats
# Tests de bin/ms-snapshot (M02-E14, version de M02-E27). Lancement : bats tests/bats
# L'API Proxmox est simulée (helpers/bin/curl, fixtures/) : aucun appel réel.
# M02-E27 : les trois tests de la fonction interne a_purger (E14) sont retirés ; la
# sélection est désormais couverte par le contrat (ms-snapshot-idempotence.bats).

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  preparer_faux_pve
  SNAP="$RACINE/bin/ms-snapshot"
}

# --- Arguments et garde-fous : rien ne doit partir vers l'API -----------------

@test "--help affiche l'usage et sort en 0" {
  run -0 "$SNAP" --help
  [[ "$output" == *"Usage : ms-snapshot"* ]]
}

@test "une option inconnue est une erreur d'usage (2)" {
  run -2 "$SNAP" --force 2020
  [[ "$(appels '^(GET|POST|DELETE)')" -eq 0 ]]
}

@test "sans cible : erreur d'usage (2)" {
  run -2 "$SNAP"
}

@test "--keep 0 est refusé (2) : il supprimerait l'instantané qu'on vient de créer" {
  run -2 "$SNAP" --keep 0 2020
  run -2 "$SNAP" --keep=abc 2020
}

@test "une option sans valeur est une erreur d'usage (2)" {
  run -2 "$SNAP" 2020 --keep
}

@test "--pool et des VMID ensemble : erreur d'usage (2)" {
  run -2 "$SNAP" --pool lab 2020
}

@test "un préfixe invalide est une erreur d'usage (2)" {
  run -2 "$SNAP" --prefix 1avant 2020
  run -2 "$SNAP" --prefix "avant maj" 2020
  run -2 "$SNAP" --prefix abcdefghijklmnopqrstuvwxy 2020
  [[ "$(appels '^(GET|POST|DELETE)')" -eq 0 ]]
}

@test "un autre pool que lab est refusé (3)" {
  run -3 "$SNAP" --pool production
}

@test "une VM invisible ou hors pool est refusée (3), sans aucune création" {
  run -3 "$SNAP" 2020 100
  [[ "$output" == *"VM 100 introuvable"* ]]
  run -3 "$SNAP" 2029
  [[ "$output" == *"hors du pool lab"* ]]
  [[ "$(appels '^POST')" -eq 0 ]]
}

@test "un template est refusé (3)" {
  run -3 "$SNAP" 9000
  [[ "$output" == *"template"* ]]
}

# --- Exécutions complètes contre l'API simulée ---------------------------------

@test "crée l'instantané, attend la tâche, purge au-delà de --keep" {
  run -0 "$SNAP" --keep 3 2020
  [[ "$(appels '^POST /nodes/pve01/qemu/2020/snapshot snapname=avant-[0-9]{8}-[0-9]{6} ')" -eq 1 ]]
  [[ "$(appels '^GET /nodes/pve01/tasks/UPID:pve01:.*:qmsnapshot:2020:')" -eq 1 ]]
  # 4 anciens + 1 nouveau, on en garde 3 : les 2 plus anciens partent, rien d'autre.
  [[ "$(appels '^DELETE ')" -eq 2 ]]
  [[ "$(appels '^DELETE /nodes/pve01/qemu/2020/snapshot/avant-20260101-080000')" -eq 1 ]]
  [[ "$(appels '^DELETE /nodes/pve01/qemu/2020/snapshot/avant-20260102-080000')" -eq 1 ]]
  [[ "$(appels 'SECRET_DANS_ARGV|SANS_JETON')" -eq 0 ]]
}

@test "--dry-run n'envoie aucune écriture mais annonce la même purge" {
  run -0 "$SNAP" --dry-run 2020
  [[ "$(appels '^(POST|DELETE)')" -eq 0 ]]
  [[ "$output" == *"supprimerait l'ancien instantané avant-20260101-080000"* ]]
  [[ "$output" == *"supprimerait l'ancien instantané avant-20260102-080000"* ]]
}

@test "--pool lab traite toutes les VMs du pool, sauf le template" {
  run -0 "$SNAP" --pool lab --keep 5
  [[ "$(appels '^POST /nodes/pve01/qemu/[0-9]+/snapshot')" -eq 7 ]]
  [[ "$(appels '^POST /nodes/pve01/qemu/9000/')" -eq 0 ]]
  [[ "$(appels '^POST /nodes/pve01/qemu/2029/')" -eq 0 ]]
}

@test "même horodatage pour toutes les VMs d'une exécution" {
  run -0 "$SNAP" 1002 2020
  noms="$(grep -oE 'snapname=[^ ]+' "$FAUX_PVE_JOURNAL" | sort -u)"
  [[ "$(wc -l <<<"$noms")" -eq 1 ]]
}

@test "création en échec : code 1, et aucune purge sur cette VM" {
  touch "$FAUX_PVE_ETAT/snapshot-ko-2020"
  run -1 "$SNAP" 2020 1002
  [[ "$(appels '^DELETE /nodes/pve01/qemu/2020/')" -eq 0 ]]
  # L'autre VM est quand même traitée.
  [[ "$(appels '^POST /nodes/pve01/qemu/1002/snapshot')" -eq 1 ]]
  [[ "$output" == *"purge annulée"* ]]
}

@test "tâche Proxmox en échec : code 1, aucune purge" {
  touch "$FAUX_PVE_ETAT/tache-ko"
  run -1 "$SNAP" 2020
  [[ "$(appels '^DELETE')" -eq 0 ]]
}

@test "API injoignable : code 1, message clair" {
  touch "$FAUX_PVE_ETAT/reseau-ko"
  run -1 "$SNAP" 2020
  [[ "$output" == *"échec réseau ou TLS"* ]]
}

@test "une seconde exécution simultanée est refusée (3)" {
  mkdir -p "$MS_LOCK_DIR"
  flock "$MS_LOCK_DIR/ms-snapshot.lock" sleep 30 3>&- &
  local pid=$!
  sleep 0.3
  run -3 "$SNAP" 2020
  [[ "$output" == *"déjà en cours"* ]]
  [[ "$(appels '^POST')" -eq 0 ]]
  pkill -P "$pid" || true
  kill "$pid" || true
}
