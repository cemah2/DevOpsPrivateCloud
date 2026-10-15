#!/usr/bin/env bats
# Tests de bin/ms-verif-k8s-stockage (M16-E27). Aucun cluster : kubectl et curl sont remplacés par
# des fonctions (prioritaires sur les commandes du PATH) qui répondent selon des variables d'état
# préparées par chaque test. Chaque contrôle a au moins un test « rouge ».
# Prérequis : la sonde charge lib/ms-commun.sh (M02-E20) : les tests tournent dans le projet
# plateforme/outils (task test:bats, CI).
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317,SC2034
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-k8s-stockage
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-k8s-stockage"
  D="$BATS_TEST_TMPDIR"
  echo "kubeconfig simulé" >"$D/kubeconfig"

  export MS_CONF="$D/ms-verif-k8s-stockage.conf"
  cat >"$MS_CONF" <<FIN
MS_K8S_KUBECONFIG=$D/kubeconfig
MS_K8S_NOEUDS=(w1 w2)
MS_K8S_PORT_KUBELET=10250
MS_K8S_NB_TRAVAILLEURS=2
MS_K8S_ESPACE_CSI=ceph-csi
MS_K8S_NB_PILOTES=2
MS_K8S_SNAPSHOT_CONTROLLER=snapshot-controller
MS_K8S_PVC_PENDING_MIN=15
MS_K8S_SNAPSHOT_MIN=30
MS_K8S_SEUIL_VOLUME=80
MS_K8S_SAUVEGARDE_H=26
MS_K8S_RETARD_S=60
MS_K8S_ESPACE_VELERO=velero
FIN

  # Horodatages relatifs à maintenant.
  il_y_a() { date -u -d "@$(($(date +%s) - $1))" +%Y-%m-%dT%H:%M:%SZ; }
  RECENT="$(il_y_a 3600)"
  VIEUX="$(il_y_a 200000)"

  # État simulé (modifié par les tests).
  PVC_PHASE=Bound
  PVC_AGE=7200
  PV_PHASE=Bound
  VA_ERREUR=0
  DS_PRETS=2
  SNAPCTL_PRETS=1
  SNAP_PRET=true
  VOL_UTILISE=10
  KUBELET_OK=1
  BSL_PHASE=Available
  SAUV_PHASE=Completed
  SAUV_DATE="$RECENT"
  CNPG_PHASE="Cluster in healthy state"
  CNPG_PRETES=3
  ARCHIVAGE=True
  BASE_DATE="$RECENT"
  RETARD=2

  kubectl() {
    local a="$*"
    case "$a" in
      *"config view"*"users[0]"*) echo "jeton-simule"; return 0 ;;
      *"config view"*"certificate-authority-data"*) printf 'CA' | base64; return 0 ;;
      *"auth can-i"*) echo yes; return 0 ;;
      *"get persistentvolumeclaims"*)
        jq -n --arg p "$PVC_PHASE" --arg t "$(il_y_a "$PVC_AGE")" \
          '{items: [{metadata: {namespace: "mediagenda-recette", name: "donnees-valkey-0", creationTimestamp: $t},
                     spec: {storageClassName: "ceph-rbd"}, status: {phase: $p}}]}' ;;
      *"get persistentvolumes"*)
        jq -n --arg p "$PV_PHASE" '{items: [{metadata: {name: "pvc-1"}, spec: {persistentVolumeReclaimPolicy: "Delete"}, status: {phase: $p}}]}' ;;
      *"get volumeattachments"*)
        if ((VA_ERREUR)); then
          echo '{"items":[{"spec":{"nodeName":"w1","source":{"persistentVolumeName":"pvc-1"}},"status":{"attachError":{"message":"rpc error"}}}]}'
        else
          echo '{"items":[{"spec":{"nodeName":"w1","source":{"persistentVolumeName":"pvc-1"}},"status":{"attached":true}}]}'
        fi ;;
      *"get daemonsets"*)
        jq -n --argjson r "$DS_PRETS" '{items: [
          {metadata: {name: "ceph-csi-rbd-nodeplugin"}, status: {desiredNumberScheduled: 2, numberReady: $r, updatedNumberScheduled: 2}},
          {metadata: {name: "ceph-csi-cephfs-nodeplugin"}, status: {desiredNumberScheduled: 2, numberReady: 2, updatedNumberScheduled: 2}}]}' ;;
      *"get deployments"*)
        echo '{"items":[{"metadata":{"name":"ceph-csi-rbd-provisioner"},"spec":{"replicas":2},"status":{"readyReplicas":2}}]}' ;;
      *"get deployment snapshot-controller"*)
        jq -n --argjson r "$SNAPCTL_PRETS" '{status: {readyReplicas: $r}}' ;;
      *"get volumesnapshots"*)
        jq -n --argjson p "$SNAP_PRET" --arg t "$(il_y_a 7200)" \
          '{items: [{metadata: {namespace: "wb-essais", name: "s1", creationTimestamp: $t}, status: {readyToUse: $p}}]}' ;;
      *"get backupstoragelocations"*)
        jq -n --arg p "$BSL_PHASE" '{items: [{metadata: {name: "s3-01"}, status: {phase: $p}}]}' ;;
      *"get schedules"*)
        echo '{"items":[{"metadata":{"name":"quotidienne"},"spec":{}}]}' ;;
      *"get backups.velero.io"*)
        jq -n --arg p "$SAUV_PHASE" --arg d "$SAUV_DATE" \
          '{items: [{metadata: {labels: {"velero.io/schedule-name": "quotidienne"}}, status: {phase: $p, completionTimestamp: $d}}]}' ;;
      *"get clusters.postgresql.cnpg.io"*)
        jq -n --arg p "$CNPG_PHASE" --argjson r "$CNPG_PRETES" --arg a "$ARCHIVAGE" \
          '{items: [{metadata: {namespace: "mediagenda-recette", name: "mediagenda-db"},
             spec: {instances: 3, plugins: [{name: "barman-cloud.cloudnative-pg.io", isWALArchiver: true}]},
             status: {phase: $p, readyInstances: $r, currentPrimary: "mediagenda-db-1",
                      instanceNames: ["mediagenda-db-1", "mediagenda-db-2", "mediagenda-db-3"],
                      conditions: [{type: "ContinuousArchiving", status: $a}]}}]}' ;;
      *"get backups.postgresql.cnpg.io"*)
        jq -n --arg d "$BASE_DATE" '{items: [{metadata: {namespace: "mediagenda-recette"},
          spec: {cluster: {name: "mediagenda-db"}}, status: {phase: "completed", stoppedAt: $d}}]}' ;;
      *"get scheduledbackups"*)
        echo '{"items":[{"spec":{"cluster":{"name":"mediagenda-db"}}}]}' ;;
      *"get --raw"*":9187/proxy/metrics"*)
        printf '# HELP cnpg_pg_replication_lag Replication lag behind primary in seconds\ncnpg_pg_replication_lag %s\n' "$RETARD" ;;
      *) return 1 ;;
    esac
  }

  curl() {
    local url="${*: -1}"
    ((KUBELET_OK)) || return 22
    case "$url" in
      https://w*:10250/metrics)
        cat <<METRIQUES
kubelet_volume_stats_capacity_bytes{namespace="mediagenda-recette",persistentvolumeclaim="donnees-valkey-0"} 100
kubelet_volume_stats_used_bytes{namespace="mediagenda-recette",persistentvolumeclaim="donnees-valkey-0"} $VOL_UTILISE
kubelet_volume_stats_inodes{namespace="mediagenda-recette",persistentvolumeclaim="donnees-valkey-0"} 1000
kubelet_volume_stats_inodes_used{namespace="mediagenda-recette",persistentvolumeclaim="donnees-valkey-0"} 10
METRIQUES
        ;;
      *) return 7 ;;
    esac
  }
}

@test "cluster sain : code 0" {
  run main --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bilan"* ]]
}

@test "option inconnue : code 2" {
  run main --frobnicate
  [ "$status" -eq 2 ]
}

@test "configuration sans nœud : code 1 (rien à surveiller n'est pas « tout va bien »)" {
  sed -i 's/^MS_K8S_NOEUDS=.*/MS_K8S_NOEUDS=()/' "$MS_CONF"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"configuration incomplète"* ]]
}

@test "PVC Pending depuis 2 h : code 1 et nom du PVC" {
  PVC_PHASE=Pending
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"mediagenda-recette/donnees-valkey-0"* ]]
}

@test "PVC Pending depuis 5 min seulement : pas d'alerte" {
  PVC_PHASE=Pending
  PVC_AGE=300
  run main --quiet
  [ "$status" -eq 0 ]
}

@test "PV Released d'une classe Delete : code 1" {
  PV_PHASE=Released
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"pvc-1:Released"* ]]
}

@test "VolumeAttachment en erreur : code 1" {
  VA_ERREUR=1
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"rpc error"* ]]
}

@test "nodeplugin RBD non prêt sur un nœud : code 1" {
  DS_PRETS=1
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ceph-csi-rbd-nodeplugin: 1/2"* ]]
}

@test "contrôleur de snapshots arrêté : code 1" {
  SNAPCTL_PRETS=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"contrôleur de snapshots"* ]]
}

@test "VolumeSnapshot non prêt depuis 2 h : code 1" {
  SNAP_PRET=false
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"wb-essais/s1"* ]]
}

@test "volume rempli à 95 % : code 1" {
  VOL_UTILISE=95
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"donnees-valkey-0:95%"* ]]
}

@test "kubelet illisible : code 1 (pas de silence)" {
  KUBELET_OK=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"métriques du kubelet illisibles"* ]]
}

@test "BSL indisponible : code 1" {
  BSL_PHASE=Unavailable
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"s3-01:Unavailable"* ]]
}

@test "planification sans sauvegarde réussie : code 1" {
  SAUV_PHASE=PartiallyFailed
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"aucune sauvegarde réussie"* ]]
}

@test "dernière sauvegarde Velero trop ancienne : code 1" {
  SAUV_DATE="$VIEUX"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"quotidienne : dernière sauvegarde réussie il y a"* ]]
}

@test "Cluster PostgreSQL non sain : code 1" {
  CNPG_PHASE="Failing over"
  CNPG_PRETES=2
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failing over, 2/3"* ]]
}

@test "archivage des WAL en échec : code 1" {
  ARCHIVAGE=False
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"archivage continu des WAL en échec"* ]]
}

@test "sauvegarde de base trop ancienne : code 1" {
  BASE_DATE="$VIEUX"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"dernière sauvegarde de base il y a"* ]]
}

@test "retard de réplication de 300 s : code 1" {
  RETARD=300
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"retard de 300 s"* ]]
}
