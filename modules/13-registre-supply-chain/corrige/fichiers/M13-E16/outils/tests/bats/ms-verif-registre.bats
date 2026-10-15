#!/usr/bin/env bats
# Tests de bin/ms-verif-registre (M13-E16). Aucun accès réseau : curl et openssl sont remplacés par des
# fonctions (prioritaires sur les commandes du PATH) qui répondent selon des variables d'état préparées
# par chaque test. Chaque contrôle a au moins un test « rouge ».
# Prérequis : bin/ms-verif-registre charge lib/ms-commun.sh (M02-E20) : les tests tournent dans le
# projet plateforme/outils (task test:bats, CI).
# shellcheck disable=SC2329,SC2317,SC2034
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-registre
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-registre"
  D="$BATS_TEST_TMPDIR"
  export MS_CONF="$D/ms-verif-registre.conf" MS_REG_SECRET="$D/secret"
  cat >"$MS_CONF" <<'FIN'
MS_REG_URL=https://registry.test
MS_REG_NOM=registry.test
MS_REG_METRIQUES=http://reg01.test:9090/metrics
MS_RACINE=/dev/null
MS_REG_VERSION=v2.15.3
MS_REG_REPLICATION_MAX_H=26
MS_REG_GC_MAX_JOURS=8
FIN
  # Format du secret : affectations shell, valeur du nom ENTRE APOSTROPHES (le « $ » du nom de robot).
  printf "HARBOR_USER='robot\$supervision'\nHARBOR_PASSWORD='x'\n" >"$MS_REG_SECRET"
  chmod 600 "$MS_REG_SECRET"

  # État simulé (modifié par les tests).
  SANTE=healthy
  COMPOSANT_KO=""
  METRIQUES=1
  VERSION=v2.15.3-abcdef
  TOTAL=1000
  LIBRE=500
  POLITIQUES='[{"id":1,"name":"medisphere-vers-reg02","enabled":true}]'
  REPL_STATUT=Succeed
  REPL_AGE_H=3
  GC_STATUT=Success
  GC_AGE_H=30
  CERT_OK=1
  CERT_JOURS=25

  iso() { date -u -d "@$(($(date +%s) - $1 * 3600))" +%Y-%m-%dT%H:%M:%SZ; }

  curl() {
    local url="${*: -1}"
    case "$url" in
      */api/v2.0/health)
        if [[ "$SANTE" == absent ]]; then return 7; fi
        printf '{"status":"%s","components":[{"name":"core","status":"healthy"},{"name":"database","status":"%s"}]}' \
          "$SANTE" "$([[ "$COMPOSANT_KO" == database ]] && echo unhealthy || echo healthy)"
        ;;
      */systeminfo) printf '{"harbor_version":"%s"}' "$VERSION" ;;
      */systeminfo/volumes) printf '{"storage":[{"total":%s,"free":%s}]}' "$TOTAL" "$LIBRE" ;;
      */replication/policies*) printf '%s' "$POLITIQUES" ;;
      */replication/executions*) printf '[{"status":"%s","start_time":"%s"}]' "$REPL_STATUT" "$(iso "$REPL_AGE_H")" ;;
      */system/gc*) printf '[{"job_status":"%s","creation_time":"%s"}]' "$GC_STATUT" "$(iso "$GC_AGE_H")" ;;
      */metrics)
        if ((METRIQUES)); then printf 'harbor_up{component="core"} 1\nharbor_health 1\n'; else return 22; fi
        ;;
      *) return 7 ;;
    esac
  }

  openssl() {
    case "$1" in
      s_client) ((CERT_OK)) && echo "-----BEGIN CERTIFICATE-----" || return 1 ;;
      x509)
        if [[ " $* " == *" -checkend "* ]]; then
          local a s=0 prochain=0
          for a in "$@"; do
            if ((prochain)); then s="$a"; prochain=0; fi
            [[ "$a" == -checkend ]] && prochain=1
          done
          ((CERT_JOURS * 86400 > s))
        elif [[ " $* " == *" -enddate "* ]]; then
          echo "notAfter=Nov  1 00:00:00 2026 GMT"
        else
          cat
        fi
        ;;
    esac
  }
}

@test "registre sain : code 0" {
  run main --quiet
  [ "$status" -eq 0 ]
}

@test "option inconnue : code 2" {
  run main --pas-une-option
  [ "$status" -eq 2 ]
}

@test "santé : Harbor injoignable" {
  SANTE=absent
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  sante"* ]]
}

@test "santé : un composant en défaut est nommé" {
  SANTE=unhealthy
  COMPOSANT_KO=database
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"database"* ]]
}

@test "version : autre que celle attendue" {
  VERSION=v2.15.2-abc
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  version"* ]]
}

@test "disque : au-dessus du seuil" {
  LIBRE=100
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  disque"* ]]
}

@test "disque : seuil réglable par option" {
  LIBRE=300
  run main --seuil-disque 60
  [ "$status" -eq 1 ]
}

@test "réplication : dernière exécution en échec" {
  REPL_STATUT=Failed
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  replication"* ]]
}

@test "réplication : trop ancienne" {
  REPL_AGE_H=40
  run main
  [ "$status" -eq 1 ]
}

@test "réplication : aucune politique active n'est pas une anomalie" {
  POLITIQUES='[{"id":1,"name":"x","enabled":false}]'
  run main --quiet
  [ "$status" -eq 0 ]
}

@test "ramasse-miettes : en échec" {
  GC_STATUT=Error
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  gc"* ]]
}

@test "ramasse-miettes : pas tourné depuis plus de 8 jours" {
  GC_AGE_H=300
  run main
  [ "$status" -eq 1 ]
}

@test "métriques : absentes" {
  METRIQUES=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  metriques"* ]]
}

@test "certificat : non reconnu" {
  CERT_OK=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  certificat"* ]]
}

@test "certificat : expire bientôt" {
  CERT_JOURS=5
  run main
  [ "$status" -eq 1 ]
}

@test "secret lisible par le groupe : refus" {
  chmod 640 "$MS_REG_SECRET"
  run main
  [ "$status" -eq 1 ]
}
