#!/usr/bin/env bats
# Tests de bin/ms-verif-openstack (M10-E26). Aucun accès réseau : openstack, ssh, openssl et
# timeout sont remplacés par des fonctions (prioritaires sur les commandes du PATH) qui répondent
# selon des variables d'état préparées par chaque test. Chaque domaine a au moins un test « rouge ».
# Prérequis : bin/ms-verif-openstack charge lib/ms-commun.sh (plateforme/outils, M02-E20) : les tests
# tournent dans le projet plateforme/outils (task test:bats, CI).
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-openstack
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-openstack"
  D="$BATS_TEST_TMPDIR"

  export MS_CONF="$D/ms-verif-openstack.conf"
  cat >"$MS_CONF" <<'FIN'
MS_OS_CLOUD=medisphere-supervision
MS_OS_NOEUDS=(osctl01 oscmp01 oscmp02)
MS_OS_CALCULS=(oscmp01 oscmp02)
MS_OS_CINDER_BINAIRES=(cinder-scheduler cinder-volume cinder-backup)
MS_OS_SEUIL_DISQUE=85
MS_RACINE=/dev/null
MS_POINTS_TLS=(openstack.par1.medisphere.internal:5000)
FIN

  # État simulé du cloud (modifié par les tests).
  JETON=1
  CMP02_ETAT=up
  CMP02_STATUT=enabled
  CMP02_RAISON=""
  GW_VIVANT=true
  BACKUP_ETAT=up
  LB_OPER=ONLINE
  MALADES=""
  DISQUE=42
  CERT_JOURS=25
  SSH_OK=1

  timeout() { shift; "$@"; }
  openstack() {
    local a="$*"
    case "$a" in
      *"token issue"*) ((JETON)) ;;
      *"compute service list"*)
        printf '[{"Binary":"nova-scheduler","Host":"osctl01","Status":"enabled","State":"up","Disabled Reason":null},
                 {"Binary":"nova-conductor","Host":"osctl01","Status":"enabled","State":"up","Disabled Reason":null},
                 {"Binary":"nova-compute","Host":"oscmp01","Status":"enabled","State":"up","Disabled Reason":null},
                 {"Binary":"nova-compute","Host":"oscmp02","Status":"%s","State":"%s","Disabled Reason":"%s"}]\n' \
          "$CMP02_STATUT" "$CMP02_ETAT" "$CMP02_RAISON" ;;
      *"network agent list"*)
        printf '[{"Agent Type":"OVN Controller Gateway agent","Host":"osctl01","Alive":%s},
                 {"Agent Type":"OVN Controller agent","Host":"oscmp01","Alive":true},
                 {"Agent Type":"OVN Metadata agent","Host":"oscmp01","Alive":true}]\n' "$GW_VIVANT" ;;
      *"volume service list"*)
        printf '[{"Binary":"cinder-scheduler","Host":"osctl01","Status":"enabled","State":"up"},
                 {"Binary":"cinder-volume","Host":"osctl01@rbd-1","Status":"enabled","State":"up"},
                 {"Binary":"cinder-backup","Host":"osctl01","Status":"enabled","State":"%s"}]\n' "$BACKUP_ETAT" ;;
      *"loadbalancer list"*)
        printf '[{"name":"agenda-recette-lb","provisioning_status":"ACTIVE","operating_status":"%s"}]\n' "$LB_OPER" ;;
      *) return 1 ;;
    esac
  }
  ssh() {
    ((SSH_OK)) || return 255
    local a="$*"
    case "$a" in
      *"health=unhealthy"*) [[ "$a" == *oscmp02* ]] && printf '%s' "$MALADES"; return 0 ;;
      *"status=exited"*) return 0 ;;
      *df*) printf 'Use%%\n %s%%\n' "$DISQUE" ;;
      *) return 0 ;;
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

@test "keystone : pas de jeton → code 1" {
  JETON=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"aucun jeton"* ]]
}

@test "calcul : nova-compute activé mais down → code 1" {
  CMP02_ETAT=down
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"nova-compute sur oscmp02 : activé mais « down »"* ]]
}

@test "calcul : désactivé avec raison → normal ; sans raison → code 1" {
  CMP02_STATUT=disabled
  CMP02_RAISON="PLAT-1155 maintenance mémoire"
  run main
  [[ "$status" -eq 0 ]]
  CMP02_RAISON=""
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"désactivé SANS raison"* ]]
}

@test "réseau : passerelle OVN morte → code 1" {
  GW_VIVANT=false
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"OVN Controller Gateway agent sur osctl01 : mort"* ]]
}

@test "volumes : cinder-backup down → code 1" {
  BACKUP_ETAT=down
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"cinder-backup : absent, désactivé ou « down »"* ]]
}

@test "octavia : répartiteur OFFLINE → code 1" {
  LB_OPER=OFFLINE
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"agenda-recette-lb : ACTIVE / OFFLINE"* ]]
}

@test "nœuds : conteneur unhealthy → code 1" {
  MALADES="nova_compute"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"oscmp02 : unhealthy : nova_compute"* ]]
}

@test "nœuds : disque plein → code 1" {
  DISQUE=91
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"occupé à 91 %"* ]]
}

@test "nœuds injoignables : contrôle impossible, jamais un faux succès" {
  SSH_OK=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"injoignable en SSH : contrôle impossible"* ]]
}

@test "API muette : listes illisibles → code 1" {
  openstack() { return 1; }
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"contrôle impossible"* ]]
}

@test "certificats : un seuil absurde (400 jours) fait échouer le contrôle" {
  run main -s 400
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"expire dans moins de 400 jours"* ]]
}

@test "configuration vide : rien à surveiller n'est pas « tout va bien »" {
  printf 'MS_OS_CLOUD=x\nMS_OS_NOEUDS=()\nMS_OS_CALCULS=()\nMS_POINTS_TLS=()\nMS_OS_CINDER_BINAIRES=()\n' >"$MS_CONF"
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
}
