#!/usr/bin/env bats
# Tests de ms-verif-reseau (M07-E29) : états simulés par des fichiers JSON (MS_ETAT_DIR), aucun
# accès réseau ; les URL publiées ne sont pas testées ici (MS_URLS vide dans la configuration d'essai).

setup() {
  RACINE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SONDE="$RACINE/bin/ms-verif-reseau"
  TMP="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME"/donnees/nominal/*.json "$TMP/"
  export MS_ETAT_DIR="$TMP"
  export MS_CONF="$TMP/essai.conf"
  sed -e 's/^MS_URLS=(/MS_URLS_INUTILISE=(/' "$RACINE/etc/ms-verif-reseau.conf" >"$MS_CONF"
  echo 'MS_URLS=()' >>"$MS_CONF"
}

teardown() {
  rm -rf "$TMP"
}

# modifier HOTE FILTRE_JQ — applique un filtre au JSON simulé d'un hôte.
modifier() {
  jq "$2" "$TMP/$1.json" >"$TMP/$1.tmp" && mv "$TMP/$1.tmp" "$TMP/$1.json"
}

@test "nominal : code 0, aucune anomalie" {
  run "$SONDE" --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 anomalie"* ]]
}

@test "option inconnue : code 2" {
  run "$SONDE" --nimporte-quoi
  [ "$status" -eq 2 ]
}

@test "VIP sur les deux passerelles : cerveau divisé détecté" {
  modifier gw02 '.adresses += [{"interface":"ens19.99","adresse":"10.10.99.1","longueur":24}]'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"10.10.99.1 portée par 2 hôtes"* ]]
}

@test "VIP sur aucune passerelle" {
  modifier gw01 '.adresses |= map(select(.adresse != "10.10.20.1"))'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"10.10.20.1 portée par AUCUN"* ]]
}

@test "VIP réparties sur les deux passerelles : groupe rompu" {
  modifier gw01 '.adresses |= map(select(.adresse != "10.10.30.1"))'
  modifier gw02 '.adresses += [{"interface":"ens19.30","adresse":"10.10.30.1","longueur":24}]'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"groupe de synchronisation rompu"* ]]
}

@test "passerelle muette : contrôle impossible = anomalie" {
  rm "$TMP/gw02.json"
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"gw02.par1.medisphere.internal : état illisible"* ]]
}

@test "keepalived arrêté sur la passerelle de secours : plus de redondance" {
  modifier gw02 '.keepalived = false'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"plus de redondance"* ]]
}

@test "serveur DOWN derrière un répartiteur" {
  modifier lb02 '.haproxy[1].etat = "DOWN"'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"lb02 : be_netbox/nbx01 DOWN"* ]]
}

@test "tunnel muet sur le maître" {
  modifier gw01 '.wireguard[0].age_s = 900'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"wg0, poignée de main 900"* ]]
}

@test "session BGP attendue tombée" {
  modifier gw01 '.bgp[0].etat = "Active"'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"session 10.10.99.251 Active"* ]]
}

@test "voisin désactivé (Admin) : pas d'anomalie" {
  modifier gw02 '.bgp += [{"voisin":"10.10.40.51","etat":"Idle (Admin)","depuis_ms":99999999}]'
  run "$SONDE" --quiet
  [ "$status" -eq 0 ]
}

@test "conntrackd arrêté" {
  modifier gw02 '.conntrackd = false'
  run "$SONDE" --quiet
  [ "$status" -eq 1 ]
}

@test "--prometheus écrit un fichier lisible" {
  run "$SONDE" --quiet --prometheus "$TMP/reseau.prom"
  [ "$status" -eq 0 ]
  grep -q '^ms_reseau_anomalies 0$' "$TMP/reseau.prom"
  grep -q '^ms_reseau_vip_porteurs{vip="10.10.99.1"} 1$' "$TMP/reseau.prom"
}
