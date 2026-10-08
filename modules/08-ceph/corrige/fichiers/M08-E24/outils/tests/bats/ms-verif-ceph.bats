#!/usr/bin/env bats
# Tests de bin/ms-verif-ceph (M08-E24). Aucun accès réseau : curl et openssl sont remplacés par des
# fonctions (prioritaires sur les commandes du PATH) qui répondent selon des variables d'état
# préparées par chaque test. Chaque contrôle a au moins un test « rouge ».
# Prérequis : bin/ms-verif-ceph charge lib/ms-commun.sh (M02-E20) : les tests tournent dans le projet
# plateforme/outils (task test:bats, CI), pas dans le dossier du corrigé seul.
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-ceph
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-ceph"
  D="$BATS_TEST_TMPDIR"

  export MS_CONF="$D/ms-verif-ceph.conf"
  cat >"$MS_CONF" <<'FIN'
MS_CEPH_MGR_HOTES=(ceph01 ceph02 ceph03)
MS_CEPH_PORT_METRIQUES=9283
MS_CEPH_MONS=3
MS_CEPH_OSDS=3
MS_CEPH_SEUIL_BRUT=40
MS_CEPH_S3_URL=https://rgw.par1.medisphere.internal
MS_RACINE=/dev/null
MS_CEPH_POINTS_TLS=(rgw.par1.medisphere.internal:443)
FIN

  # État simulé du cluster (modifié par les tests).
  MGR_ACTIFS="ceph01"
  SANTE=0
  CONTROLES=""
  QUORUM="1 1 1"
  OSD_UP="1 1 1"
  OSD_IN="1 1 1"
  PG_TOTAL=64
  PG_ACTIFS=64
  PG_PROPRES=64
  POOL_STOCKE=10
  POOL_DISPO=90
  BRUT_UTILISE=30
  S3_CODE=200
  CERT_OK=1
  CERT_JOURS=25

  metriques() {
    local i=0 v
    echo "# HELP ceph_health_status Cluster health status"
    echo "ceph_health_status $SANTE.0"
    for v in $CONTROLES; do echo "ceph_health_detail{name=\"$v\",severity=\"HEALTH_WARN\"} 1.0"; done
    echo 'ceph_health_detail{name="OSD_DOWN",severity="HEALTH_WARN"} 0.0'
    for v in $QUORUM; do i=$((i + 1)); echo "ceph_mon_quorum_status{ceph_daemon=\"mon.ceph0$i\"} $v.0"; done
    i=0
    for v in $OSD_UP; do echo "ceph_osd_up{ceph_daemon=\"osd.$i\"} $v.0"; i=$((i + 1)); done
    i=0
    for v in $OSD_IN; do echo "ceph_osd_in{ceph_daemon=\"osd.$i\"} $v.0"; i=$((i + 1)); done
    echo "ceph_pg_total{pool_id=\"1\"} $PG_TOTAL.0"
    echo "ceph_pg_active{pool_id=\"1\"} $PG_ACTIFS.0"
    echo "ceph_pg_clean{pool_id=\"1\"} $PG_PROPRES.0"
    echo 'ceph_pool_metadata{pool_id="1",name="rbd-test",type="replicated",description="replica:3"} 1.0'
    echo "ceph_pool_stored{pool_id=\"1\"} $POOL_STOCKE.0"
    echo "ceph_pool_max_avail{pool_id=\"1\"} $POOL_DISPO.0"
    echo 'ceph_cluster_total_bytes 100.0'
    echo "ceph_cluster_total_used_bytes $BRUT_UTILISE.0"
  }

  curl() {
    local url="${*: -1}" h
    case "$url" in
      http://*:9283/metrics)
        h="${url#http://}"
        h="${h%%:*}"
        if [[ " $MGR_ACTIFS " == *" $h "* ]]; then metriques; return 0; fi
        return 22
        ;;
      https://rgw.*)
        printf '%s' "$S3_CODE"
        return 0
        ;;
    esac
    return 7
  }

  openssl() {
    case "$1" in
      s_client)
        ((CERT_OK)) || return 1
        echo "-----BEGIN CERTIFICATE-----"
        ;;
      x509)
        case "$*" in
          *-checkend*)
            local a="$*" s
            s="${a##*-checkend }"
            s="${s%% *}"
            ((CERT_JOURS * 86400 > s))
            ;;
          *-enddate*) echo "notAfter=Nov  1 00:00:00 2026 GMT" ;;
          *) cat ;;
        esac
        ;;
    esac
  }
}

@test "cluster sain : code 0" {
  run main --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bilan"* ]]
}

@test "aucun mgr actif : code 1, le cluster n'est pas déclaré sain" {
  MGR_ACTIFS=""
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"aucun mgr actif"* ]]
  [[ "$output" != *"HEALTH_OK"* ]]
}

@test "deux hôtes servent des métriques : code 1" {
  MGR_ACTIFS="ceph01 ceph02"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"plusieurs hôtes"* ]]
}

@test "HEALTH_WARN : code 1 et nom du contrôle actif (pas des inactifs)" {
  SANTE=1
  CONTROLES="OSDMAP_FLAGS"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"HEALTH_WARN : OSDMAP_FLAGS"* ]]
  [[ "$output" != *"OSD_DOWN"* ]]
}

@test "quorum incomplet : code 1" {
  QUORUM="1 1 0"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 moniteur(s) sur 3"* ]]
}

@test "OSD down : code 1, OSD nommé" {
  OSD_UP="1 0 1"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"osd.1:down"* ]]
}

@test "OSD out : code 1" {
  OSD_IN="1 1 0"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"osd.2:out"* ]]
}

@test "OSD manquant dans les métriques : code 1" {
  OSD_UP="1 1"
  OSD_IN="1 1"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 OSD connus, 3 attendus"* ]]
}

@test "PG non propres : code 1" {
  PG_PROPRES=60
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"4 non propre(s)"* ]]
}

@test "pool au-dessus du seuil : code 1" {
  POOL_STOCKE=85
  POOL_DISPO=15
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"rbd-test plein à 85 %"* ]]
}

@test "seuil de pool à 0 % : code 1 (sert au check)" {
  run main --seuil-pool 0
  [ "$status" -eq 1 ]
}

@test "occupation brute au-delà de la réserve : code 1" {
  BRUT_UTILISE=50
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"occupé à 50 %"* ]]
}

@test "S3 en erreur : code 1" {
  S3_CODE=503
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 503"* ]]
}

@test "certificat non vérifié : code 1" {
  CERT_OK=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"chaîne non reconnue"* ]]
}

@test "certificat proche de l'expiration : code 1" {
  CERT_JOURS=5
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"expire dans moins de 10 jours"* ]]
}

@test "option inconnue : code 2" {
  run main --nimporte-quoi
  [ "$status" -eq 2 ]
}

@test "seuil invalide : code 2" {
  run main --seuil-pool 150
  [ "$status" -eq 2 ]
}

@test "configuration vide : code 1, jamais « tout va bien »" {
  printf 'MS_CEPH_MGR_HOTES=()\nMS_CEPH_MONS=0\nMS_CEPH_OSDS=0\n' >"$MS_CONF"
  run main
  [ "$status" -eq 1 ]
}
