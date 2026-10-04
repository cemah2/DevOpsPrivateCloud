#!/usr/bin/env bats
# Tests de bin/ms-verif-sauvegardes (M02-E26). Aucun accès réseau : pve_api et pbs_api sont
# remplacés par des fonctions qui lisent des données préparées dans un répertoire temporaire.
# Ces fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329
# shellcheck source-path=SCRIPTDIR

setup() {
  # Charge le script sans exécuter main (garde BASH_SOURCE en fin de script).
  # shellcheck source=../../bin/ms-verif-sauvegardes
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-sauvegardes"
  DONNEES="$BATS_TEST_TMPDIR"
  MAINTENANT="$(date +%s)"
  export MS_PBS_ENV_FILE="$DONNEES/pbs.env"
  cat >"$MS_PBS_ENV_FILE" <<'FIN'
PBS_API_URL=https://pbs.invalid:8007/api2/json
PBS_DATASTORE=ds-lab
PBS_NAMESPACE=par1
PBS_TOKEN_ID=test@pbs!lecture
PBS_TOKEN_SECRET=secret-de-test
PBS_PINNEDPUBKEY=sha256//AAAA
FIN
  chmod 600 "$MS_PBS_ENV_FILE"
  # Trois VMs du socle (dont une hors pool et un template à ignorer)
  cat >"$DONNEES/ressources.json" <<'FIN'
[
  {"vmid": 1000, "name": "gw01",  "pool": "lab", "tags": "role-routeur;socle", "template": 0},
  {"vmid": 1002, "name": "dns01", "pool": "lab", "tags": "socle;role-dns"},
  {"vmid": 1004, "name": "git01", "pool": "lab", "tags": "socle;role-gitlab"},
  {"vmid": 2021, "name": "m02-x", "pool": "lab", "tags": "env-m02"},
  {"vmid": 9000, "name": "tpl",   "pool": "lab", "tags": "socle", "template": 1},
  {"vmid": 104,  "name": "perso", "tags": "socle"}
]
FIN
  pve_api() { cat "$DONNEES/ressources.json"; }
  pbs_api() { cat "$DONNEES/instantanes.json"; }
}

# instantane VMID AGE_HEURES [ETAT_VERIF] — un objet JSON d'instantané PBS
instantane() {
  local verif=""
  [[ -n "${3:-}" ]] && verif=", \"verification\": {\"state\": \"$3\", \"upid\": \"UPID:x\"}"
  printf '{"backup-type": "vm", "backup-id": "%s", "backup-time": %d, "files": [], "protected": false%s}' \
    "$1" "$((MAINTENANT - $2 * 3600))" "$verif"
}

@test "toutes les VMs du socle sauvegardées récemment : code 0" {
  printf '[%s,%s,%s,%s]' "$(instantane 1000 5 ok)" "$(instantane 1000 30 ok)" \
    "$(instantane 1002 4)" "$(instantane 1004 6 ok)" >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"gw01"* && "$output" == *"dns01"* && "$output" == *"git01"* ]]
  # Le template, la VM hors pool et la VM sans étiquette socle sont ignorés
  [[ "$output" != *"tpl"* && "$output" != *"perso"* && "$output" != *"m02-x"* ]]
}

@test "une sauvegarde trop ancienne : code 1 et VM signalée" {
  printf '[%s,%s,%s]' "$(instantane 1000 5)" "$(instantane 1002 27)" "$(instantane 1004 6)" \
    >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"dns01"*"trop ancienne"* ]]
}

@test "une VM sans aucune sauvegarde : code 1" {
  printf '[%s,%s]' "$(instantane 1000 5)" "$(instantane 1004 6)" >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"dns01"*"aucune sauvegarde"* ]]
}

@test "dernière vérification en échec : code 1" {
  printf '[%s,%s,%s]' "$(instantane 1000 5)" "$(instantane 1002 4 failed)" "$(instantane 1004 6)" \
    >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"vérification en échec"* ]]
}

@test "seuil réglable : --age-max 4 rend la sauvegarde de 5 h trop ancienne" {
  printf '[%s,%s,%s]' "$(instantane 1000 5)" "$(instantane 1002 3)" "$(instantane 1004 2)" \
    >"$DONNEES/instantanes.json"
  run main --age-max 4
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"gw01"*"trop ancienne"* ]]
}

@test "aucune VM visible (droits insuffisants) : échec, jamais un faux succès" {
  echo '[]' >"$DONNEES/ressources.json"
  echo '[]' >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"aucune VM"* ]]
}

@test "API PBS en erreur : code 1" {
  pbs_api() { return 1; }
  run main
  [[ "$status" -eq 1 ]]
}

@test "fichier de configuration PBS lisible par tous : refus" {
  chmod 644 "$MS_PBS_ENV_FILE"
  printf '[%s]' "$(instantane 1000 5)" >"$DONNEES/instantanes.json"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"chmod 600"* ]]
}

@test "usage : option inconnue et seuil invalide renvoient 2" {
  run main --nimporte-quoi
  [[ "$status" -eq 2 ]]
  run main --age-max 08h
  [[ "$status" -eq 2 ]]
}
