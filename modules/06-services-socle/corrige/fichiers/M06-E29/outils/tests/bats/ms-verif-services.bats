#!/usr/bin/env bats
# Tests de bin/ms-verif-services (M06-E29). Aucun accès réseau : dig, curl et openssl sont
# remplacés par des fonctions (prioritaires sur les commandes du PATH) qui répondent selon des
# variables d'état préparées par chaque test. Chaque domaine a au moins un test « rouge ».
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-services
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-services"
  D="$BATS_TEST_TMPDIR"

  # Configuration réduite mais complète.
  export MS_CONF="$D/ms-verif-services.conf"
  cat >"$MS_CONF" <<'FIN'
MS_RESOLVEURS=(10.10.20.10 10.10.20.16)
MS_AUTORITAIRES=(10.10.20.10 10.10.20.16)
MS_PORT_AUTORITAIRE=5300
MS_ZONES=(par1.medisphere.internal 10.10.in-addr.arpa)
MS_ZONES_SIGNEES=(par1.medisphere.internal)
MS_NOM_INTERNE=git01.par1.medisphere.internal
MS_NOM_INTERNET=deb.debian.org
MS_KEA=(10.10.20.10 10.10.20.16)
MS_KEA_PORT=8004
MS_KEA_SOUS_RESEAU=99
MS_KEA_LIBRES_MIN=10
MS_NETBOX_URL=https://nbx01.par1.medisphere.internal
MS_NETBOX_VERSION='^4\.6\.'
MS_CA_URL=https://ca01.par1.medisphere.internal
MS_RACINE=/dev/null
MS_POINTS_TLS=(git01.par1.medisphere.internal:443 dns01.par1.medisphere.internal:8004)
FIN
  export MS_KEA_ENV_FILE="$D/kea.env"
  printf 'KEA_API_USER=supervision\nKEA_API_PASSWORD=essai\n' >"$MS_KEA_ENV_FILE"
  chmod 600 "$MS_KEA_ENV_FILE"
  export MS_NETBOX_TOKEN_FILE="$D/netbox.token"
  printf 'nbt_essai.jeton-de-test\n' >"$MS_NETBOX_TOKEN_FILE"
  chmod 600 "$MS_NETBOX_TOKEN_FILE"

  # État simulé du socle (modifié par les tests).
  SERIAL_A=2026100701
  SERIAL_B=2026100701
  AD=1
  KEA_ETAT=hot-standby
  KEA_CONTACT=true
  KEA_OCCUPEES=12
  CERT_JOURS=25

  dig() {
    local a="$*"
    case "$a" in
      *sonde-inexistante*) echo ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 4242' ;;
      *+dnssec*)
        if ((AD)); then echo ';; flags: qr rd ra ad; QUERY: 1, ANSWER: 2'; else echo ';; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 1'; fi ;;
      *@10.10.20.10*SOA*) echo "dns01.par1.medisphere.internal. hostmaster.par1.medisphere.internal. $SERIAL_A 10800 3600 604800 300" ;;
      *@10.10.20.16*SOA*) echo "dns01.par1.medisphere.internal. hostmaster.par1.medisphere.internal. $SERIAL_B 10800 3600 604800 300" ;;
      *) echo '10.10.20.12' ;;
    esac
  }
  curl() {
    local a="$*"
    cat >/dev/null # configuration -K - lue sur stdin
    case "$a" in
      *status-get*)
        printf '[{"result":0,"arguments":{"high-availability":[{"ha-mode":"hot-standby","ha-servers":{"local":{"role":"primary","state":"%s"},"remote":{"in-touch":%s}}}]}}]\n' \
          "$KEA_ETAT" "$KEA_CONTACT" ;;
      *total-addresses*) echo '[{"result":0,"arguments":{"subnet[99].total-addresses":[[100,"2026-10-07 10:00:00"]]}}]' ;;
      *assigned-addresses*) printf '[{"result":0,"arguments":{"subnet[99].assigned-addresses":[[%s,"2026-10-07 10:00:00"]]}}]\n' "$KEA_OCCUPEES" ;;
      */api/status/*) echo '{"netbox-version":"4.6.2","python-version":"3.13.5"}' ;;
      */health*) echo '{"status":"ok"}' ;;
      *) return 22 ;;
    esac
  }
  openssl() {
    case "$1 ${2:-}" in
      "s_client "*) echo 'CERTIFICAT-SIMULÉ' ;;
      "x509 ") cat ;;
      "x509 -noout")
        if [[ "$3" == -checkend ]]; then
          (($4 < CERT_JOURS * 86400))
        else
          echo 'notAfter=Nov  1 10:00:00 2026 GMT'
        fi ;;
    esac
  }
}

@test "tout va bien : code 0, aucune anomalie" {
  run main
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"0 anomalie(s)"* ]]
  [[ "$output" != *"KO "* ]]
}

@test "réplication : numéros de série différents → code 1" {
  SERIAL_B=2026100600
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"numéros de série différents"* ]]
}

@test "dnssec : réponse non validée (pas de drapeau ad) → code 1" {
  AD=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"ne valide pas par1.medisphere.internal"* ]]
}

@test "dhcp : pair perdu (partner-down) → code 1" {
  KEA_ETAT=partner-down
  KEA_CONTACT=false
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"état partner-down"* ]]
}

@test "dhcp : plage presque pleine → code 1" {
  KEA_OCCUPEES=95
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"plus que 5 adresse(s) libre(s)"* ]]
}

@test "certificats : expiration sous le seuil → code 1 ; seuil abaissé → code 0" {
  CERT_JOURS=5
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"expire dans moins de 10 jours"* ]]
  run main --seuil-certificats 3
  [[ "$status" -eq 0 ]]
}

@test "certificats : un seuil absurde (400 jours) fait échouer le contrôle" {
  run main -s 400
  [[ "$status" -eq 1 ]]
}

@test "identité Kea lisible par d'autres : contrôle impossible, jamais un faux succès" {
  chmod 644 "$MS_KEA_ENV_FILE"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"contrôle impossible"* ]]
}

@test "NetBox muet : code 1" {
  curl() { cat >/dev/null; return 7; }
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"/api/status/ ne répond pas"* ]]
}

@test "configuration vide : rien à surveiller n'est pas « tout va bien »" {
  printf 'MS_RESOLVEURS=()\nMS_ZONES=()\nMS_KEA=()\nMS_POINTS_TLS=()\n' >"$MS_CONF"
  run main
  [[ "$status" -eq 1 ]]
}

@test "--quiet n'affiche que les anomalies et le bilan" {
  run main --quiet
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"OK  "* ]]
  [[ "$output" == *"Bilan"* ]]
}

@test "usage : option inconnue et seuil invalide renvoient 2" {
  run main --nimporte-quoi
  [[ "$status" -eq 2 ]]
  run main --seuil-certificats 0
  [[ "$status" -eq 2 ]]
  run main --seuil-certificats dix
  [[ "$status" -eq 2 ]]
}
