#!/usr/bin/env bats
# Tests de bin/ms-verif-cluster (M09-E25). Aucun accès réseau : pve_api (de lib/ms-commun.sh) et
# openssl sont remplacés par des fonctions qui répondent selon des variables d'état préparées par
# chaque test. Chaque domaine a au moins un test « rouge ».
# Comme pour ms-verif-services, les tests tournent dans le projet plateforme/outils (task test:bats).
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317,SC2034
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-cluster
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-cluster"
  D="$BATS_TEST_TMPDIR"

  export MS_CONF="$D/ms-verif-cluster.conf"
  cat >"$MS_CONF" <<'FIN'
MS_HV_NOEUDS=(hv01.par1.medisphere.internal hv02.par1.medisphere.internal hv03.par1.medisphere.internal)
MS_HV_NOEUDS_ATTENDUS=3
MS_HV_CEPH=1
MS_HV_STOCKAGE_SEUIL=85
MS_HV_REPLI_AGE_MAX=3600
MS_HV_POOLS_SAUVEGARDES=(prod)
MS_HV_SAUVEGARDE_AGE_MAX=93600
MS_RACINE=/dev/null
MS_VERIF_SEUIL_CERTS=10
MS_HV_VIP=hv.par1.medisphere.internal:8006
MS_HV_POINTS_TLS=(hv01.par1.medisphere.internal:8006 hv.par1.medisphere.internal:8006)
FIN

  # État simulé du cluster (modifié par les tests).
  NOEUDS_MORTS=""            # noms DNS dont l'API ne répond pas
  QUORATE=1
  HV03_EN_LIGNE=1
  SERVICE_ETAT=started
  MAITRE="hv01 (active, Wed Oct  8 10:00:00 2026)"
  CEPH=HEALTH_OK
  STOCKAGE_OCCUPE=40
  REPLI_ECHECS=0
  REPLI_AGE=300
  VZDUMP_STATUT=OK
  VZDUMP_AGE=7200
  NON_COUVERTS='[]'
  CERT_JOURS=25
  MAINTENANT=$(date +%s)
  VIP_OK=1
  joindre_tcp() { ((VIP_OK)); }

  pve_api() {
    local chemin="$2" hote="${PVE_API_URL#https://}"
    hote="${hote%%:*}"
    [[ " $NOEUDS_MORTS " == *" $hote "* ]] && return 1
    case "$chemin" in
      /cluster/status)
        printf '[{"type":"cluster","name":"hv-par1","quorate":%s,"nodes":3},' "$QUORATE"
        printf '{"type":"node","name":"hv01","online":1},{"type":"node","name":"hv02","online":1},'
        printf '{"type":"node","name":"hv03","online":%s}]\n' "$HV03_EN_LIGNE" ;;
      /cluster/ha/status/current)
        printf '[{"type":"quorum","status":"OK"},{"type":"master","status":"%s"},' "$MAITRE"
        printf '{"type":"lrm","node":"hv01","status":"hv01 (active, Wed Oct  8 10:00:00 2026)"},'
        printf '{"type":"service","sid":"vm:120","node":"hv02","state":"%s"}]\n' "$SERVICE_ETAT" ;;
      /cluster/ceph/status)
        if [[ "$CEPH" == HEALTH_OK ]]; then
          echo '{"health":{"status":"HEALTH_OK","checks":{}}}'
        else
          printf '{"health":{"status":"%s","checks":{"OSD_DOWN":{"summary":{"message":"1 osds down"}}}}}\n' "$CEPH"
        fi ;;
      /cluster/resources)
        if [[ "$3" == type=storage ]]; then
          printf '[{"storage":"ceph-vm","node":"hv01","status":"available","disk":%s,"maxdisk":100}]\n' "$STOCKAGE_OCCUPE"
        else
          echo '[{"vmid":120,"pool":"recette"},{"vmid":130,"pool":"prod"}]'
        fi ;;
      /nodes/*/replication)
        printf '[{"id":"130-0","target":"hv02","fail_count":%s,"last_sync":%s}]\n' "$REPLI_ECHECS" "$((MAINTENANT - REPLI_AGE))" ;;
      /cluster/tasks)
        printf '[{"type":"vzdump","node":"hv01","status":"%s","endtime":%s}]\n' "$VZDUMP_STATUT" "$((MAINTENANT - VZDUMP_AGE))" ;;
      /cluster/backup-info/not-backed-up) echo "$NON_COUVERTS" ;;
      *) return 1 ;;
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

@test "premier nœud muet : la sonde interroge le suivant" {
  NOEUDS_MORTS="hv01.par1.medisphere.internal"
  run main
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"réponse de hv02.par1.medisphere.internal"* ]]
}

@test "aucun nœud ne répond : contrôle impossible, code 1" {
  NOEUDS_MORTS="hv01.par1.medisphere.internal hv02.par1.medisphere.internal hv03.par1.medisphere.internal"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"contrôle impossible"* ]]
}

@test "quorum perdu → code 1" {
  QUORATE=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"SANS quorum"* ]]
}

@test "nœud hors ligne → code 1, nom du nœud dans l'alerte" {
  HV03_EN_LIGNE=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"hors ligne : hv03"* ]]
}

@test "--noeuds-attendus 4 sur un cluster de 3 → code 1" {
  run main --noeuds-attendus 4
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"3 nœud(s) en ligne sur 4"* ]]
}

@test "ha : ressource en error → code 1" {
  SERVICE_ETAT=error
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"vm:120 (error sur hv02)"* ]]
}

@test "ha : pas de maître actif → code 1" {
  MAITRE="hv01 (idle, Wed Oct  8 10:00:00 2026)"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"pas de maître HA actif"* ]]
}

@test "ceph : HEALTH_WARN → code 1 avec le motif" {
  CEPH=HEALTH_WARN
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"OSD_DOWN: 1 osds down"* ]]
}

@test "stockage plein → code 1" {
  STOCKAGE_OCCUPE=91
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"ceph-vm@hv01 91 %"* ]]
}

@test "réplication en échec, ou trop ancienne → code 1" {
  REPLI_ECHECS=2
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"130-0 → hv02 (échecs 2"* ]]
  REPLI_ECHECS=0
  REPLI_AGE=7200
  run main
  [[ "$status" -eq 1 ]]
}

@test "sauvegarde en échec, ancienne, ou invité de prod non couvert → code 1" {
  VZDUMP_STATUT="job errors"
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"dernière sauvegarde en échec"* ]]
  VZDUMP_STATUT=OK
  VZDUMP_AGE=200000
  run main
  [[ "$status" -eq 1 ]]
  VZDUMP_AGE=7200
  NON_COUVERTS='[{"vmid":130,"type":"qemu"}]'
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"130 (prod)"* ]]
}

@test "invité hors des pools surveillés non couvert : pas d'alerte" {
  NON_COUVERTS='[{"vmid":120,"type":"qemu"}]'
  run main
  [[ "$status" -eq 0 ]]
}

@test "VIP muette → code 1" {
  VIP_OK=0
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"ne répond pas (keepalived"* ]]
}

@test "certificat proche de l'expiration → code 1" {
  CERT_JOURS=5
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"expire dans moins de 10 jours"* ]]
}

@test "configuration vide : rien à surveiller n'est pas « tout va bien »" {
  printf 'MS_HV_NOEUDS=()\nMS_HV_POINTS_TLS=()\n' >"$MS_CONF"
  run main
  [[ "$status" -eq 1 ]]
}

@test "--quiet n'affiche que les anomalies et le bilan" {
  run main --quiet
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"OK  "* ]]
  [[ "$output" == *"Bilan"* ]]
}

@test "usage : option inconnue ou nombre de nœuds invalide → 2" {
  run main --nimporte-quoi
  [[ "$status" -eq 2 ]]
  run main --noeuds-attendus zero
  [[ "$status" -eq 2 ]]
  run main --noeuds-attendus
  [[ "$status" -eq 2 ]]
}
