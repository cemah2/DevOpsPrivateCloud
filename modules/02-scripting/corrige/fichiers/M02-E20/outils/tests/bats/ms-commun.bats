#!/usr/bin/env bats
# Tests de lib/ms-commun.sh (M02-E14). Lancement : bats tests/bats
# Aucun accès réseau : l'API Proxmox est simulée par helpers/bin/curl.
# shellcheck disable=SC2016  # le code entre apostrophes est évalué par avec_lib, dans un bash neuf

bats_require_minimum_version 1.5.0

setup() {
  load helpers/commun
  preparer_faux_pve
  export LIB="$RACINE/lib/ms-commun.sh"
}

# Charge la bibliothèque dans un bash neuf, en mode strict, puis exécute le code donné.
avec_lib() {
  bash -c 'set -euo pipefail; MS_PROG=test-lib; source "$LIB"; eval "$1"' _ "$1"
}

@test "la bibliothèque refuse d'être exécutée directement (code 2)" {
  run -2 bash "$LIB"
  [[ "$output" == *"bibliothèque"* ]]
}

@test "un double chargement est sans effet" {
  run -0 avec_lib 'source "$LIB"; log_info ok'
  [[ "$output" == *"INFO ok"* ]]
}

@test "log_info écrit sur stderr seulement, horodatage ISO 8601 et nom du script" {
  run -0 --separate-stderr avec_lib 'log_info "message de test"'
  [[ -z "$output" ]]
  [[ "$stderr" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}\ test-lib\[[0-9]+\]\ INFO\ message\ de\ test$ ]]
}

@test "log_warn et log_err indiquent leur niveau" {
  run -0 --separate-stderr avec_lib 'log_warn attention; log_err panne'
  [[ "${stderr_lines[0]}" == *" AVERT attention" ]]
  [[ "${stderr_lines[1]}" == *" ERREUR panne" ]]
}

@test "die quitte avec le code 1 par défaut" {
  run -1 avec_lib 'die "fin"; echo jamais'
  [[ "$output" == *"ERREUR fin"* ]]
  [[ "$output" != *jamais* ]]
}

@test "die transmet le code demandé" {
  run -3 avec_lib 'die "refus" 3'
}

@test "require_cmd liste toutes les commandes manquantes" {
  run -1 avec_lib 'require_cmd bash outil-absent-1 outil-absent-2'
  [[ "$output" == *"outil-absent-1 outil-absent-2"* ]]
}

@test "require_cmd réussit si tout est présent" {
  run -0 avec_lib 'require_cmd bash jq'
}

@test "confirm refuse sans terminal" {
  run -1 avec_lib 'confirm "Tout détruire ?" </dev/null'
  [[ "$output" == *"sans terminal"* ]]
}

@test "confirm accepte sans terminal avec MS_YES=1" {
  MS_YES=1 run -0 avec_lib 'confirm "Tout détruire ?" </dev/null'
}

@test "retry réussit dès que la commande réussit" {
  compteur="$BATS_TEST_TMPDIR/n"
  run -0 avec_lib "
    essai() { n=\$(( \$(cat '$compteur' 2>/dev/null || echo 0) + 1 )); echo \$n >'$compteur'; ((n >= 3)); }
    retry 5 0 essai"
  [[ "$(cat "$compteur")" -eq 3 ]]
}

@test "retry ne masque pas les variables de la commande appelée (portée dynamique)" {
  run -0 avec_lib 'n=0; essai() { n=$((n + 1)); ((n >= 2)); }; retry 5 0 essai; echo "n=$n"'
  [[ "$output" == *"n=2"* ]]
}

@test "retry abandonne après N tentatives et renvoie le dernier code" {
  run -4 avec_lib 'retry 3 0 bash -c "exit 4"'
  [[ "$(grep -c 'AVERT' <<<"$output")" -eq 2 ]]
  [[ "$output" == *"après 3 tentative(s)"* ]]
}

@test "retry double le délai entre deux tentatives" {
  run -1 avec_lib 'sleep() { echo "pause $1"; }; retry 4 1 false'
  [[ "$output" == *"pause 1"*"pause 2"*"pause 4"* ]]
}

@test "retry refuse un usage incorrect (code 2)" {
  run -2 avec_lib 'retry trois 1 true'
}

@test "pve_api renvoie le champ data en JSON compact" {
  run -0 --separate-stderr avec_lib 'pve_api GET /version'
  [[ "$output" = '{"version":"9.0.10","release":"9.0","repoid":"deadbeef"}' ]]
  [[ "$(appels '^GET /version')" -eq 1 ]]
}

@test "pve_api ne passe jamais le secret en argument et envoie le jeton" {
  run -0 avec_lib 'pve_api GET /version'
  [[ "$(appels 'SECRET_DANS_ARGV|SANS_JETON')" -eq 0 ]]
}

@test "pve_api restitue le motif d'une erreur HTTP (403) et renvoie 1" {
  run -1 --separate-stderr avec_lib 'pve_api GET /interdit'
  [[ -z "$output" ]]
  [[ "$stderr" == *"HTTP 403 Permission check failed (/interdit, Sys.Audit)"* ]]
}

@test "pve_api affiche le détail des erreurs de paramètres (400)" {
  run -1 avec_lib 'pve_api POST /parametres vmid=abc'
  [[ "$output" == *'"vmid":"invalid format"'* ]]
}

@test "pve_api signale une erreur réseau" {
  touch "$FAUX_PVE_ETAT/reseau-ko"
  run -1 avec_lib 'pve_api GET /version'
  [[ "$output" == *"échec réseau ou TLS (curl code 7)"* ]]
}

@test "pve_api envoie les paramètres (encodés par curl)" {
  run -0 avec_lib 'pve_api POST /nodes/pve01/qemu/2020/snapshot "snapname=essai-1" "description=deux mots"'
  grep -qF 'POST /nodes/pve01/qemu/2020/snapshot snapname=essai-1 description=deux mots' "$FAUX_PVE_JOURNAL"
}

@test "pve_api refuse un fichier d'accès lisible par les autres" {
  chmod 644 "$MS_PVE_ENV_FILE"
  run -1 avec_lib 'pve_api GET /version'
  [[ "$output" == *"mode 644"* ]]
  [[ "$(appels '^GET')" -eq 0 ]]
}

@test "les variables PVE_* de l'environnement l'emportent sur le fichier" {
  PVE_API_URL="https://ailleurs.test:8006/api2/json" run -1 avec_lib 'pve_api GET /version'
  # Le faux curl ne connaît que FAUX_PVE_BASE : le chemin reçu contient l'autre hôte.
  grep -q 'ailleurs.test' "$FAUX_PVE_JOURNAL"
}

@test "pve_api refuse une URL qui n'est pas en https" {
  PVE_API_URL="http://pve.test:8006/api2/json" run -1 avec_lib 'pve_api GET /version'
  [[ "$output" == *"https://"* ]]
}

@test "pve_wait_task réussit sur une tâche terminée OK" {
  run -0 avec_lib 'pve_wait_task "UPID:pve01:0000A1B2:00C0FFEE:6720F00D:qmsnapshot:2020:wb-automation@pve!lab:"'
  grep -qF 'GET /nodes/pve01/tasks/UPID:pve01:0000A1B2:00C0FFEE:6720F00D:qmsnapshot:2020:wb-automation@pve!lab:/status' "$FAUX_PVE_JOURNAL"
}

@test "pve_wait_task échoue sur une tâche en erreur" {
  touch "$FAUX_PVE_ETAT/tache-ko"
  run -1 avec_lib 'pve_wait_task "UPID:pve01:0000A1B2:00C0FFEE:6720F00D:qmsnapshot:2020:wb-automation@pve!lab:"'
  [[ "$output" == *"tâche en échec (snapshot feature is not available)"* ]]
}

@test "pve_wait_task refuse ce qui n'est pas un UPID" {
  run -1 avec_lib 'pve_wait_task null'
}

@test "lock_or_die : un second détenteur est refusé avec le code 3" {
  avec_lib 'lock_or_die essai; sleep 30' 3>&- &
  local pid=$!
  # Attendre que le premier détienne le verrou (le fichier contient alors son PID).
  for _ in $(seq 50); do
    grep -q '^pid' "$MS_LOCK_DIR/essai.lock" 2>/dev/null && break
    sleep 0.1
  done
  run -3 avec_lib 'lock_or_die essai'
  [[ "$output" == *"déjà en cours"* ]]
  # Tuer aussi le « sleep » : il a hérité du descripteur, donc du verrou.
  pkill -P "$pid" || true
  kill "$pid" || true
}

@test "lock_or_die : le verrou est libéré à la fin du processus" {
  run -0 avec_lib 'lock_or_die essai'
  run -0 avec_lib 'lock_or_die essai'
}
