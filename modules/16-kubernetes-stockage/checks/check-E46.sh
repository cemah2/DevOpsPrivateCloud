# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M16-E46 « Mini-projet : données Kubernetes MédiSphère v1 »
# Contrôle global de l'état k8s-stockage-v1 (à lancer depuis adm01) : stockage ceph-csi et réseau de
# stockage des travailleurs, absence de Rook, de Longhorn et de leurs disques, base mediagenda-db et
# sa sauvegarde continue, MédiAgenda, Valkey et MédiDoc, Velero planifié et testé, côté ceph-par1
# (droits et pool du consommateur Kubernetes), documentation et livraison.
# Lecture seule : kubectl (compte wb-checks), qm config en lecture sur pve01, lectures sur les
# travailleurs (ip, ping, findmnt, test -e), commandes ceph de consultation, API GitLab en GET, grep
# dans le clone local du dépôt de documentation. Les contrôles détaillés restent dans leurs exercices.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E46 — Données Kubernetes MédiSphère v1 : contrôle global"
require_cmd kubectl jq ssh curl

_m16_e46_now="$(date +%s)"
declare -A _m16_e46_ip=([k8s-w01]=10.10.30.81 [k8s-w02]=10.10.30.82 [k8s-w03]=10.10.30.83)
declare -A _m16_e46_vmid=([k8s-w01]=2144 [k8s-w02]=2145 [k8s-w03]=2146)

# --- 1. Stockage du cluster ----------------------------------------------------------------------
title "1/8 Classes, pilotes et instantanés"
_m16_e46_sc="$(_m16x_j storageclass)"
check_cmd "classes ceph-rbd, ceph-rbd-retain et cephfs présentes, pilotes ceph-csi" _m16x_q "$_m16_e46_sc" '
  ([.items[] | {(.metadata.name): .provisioner}] | add) as $p
  | $p["ceph-rbd"] == "rbd.csi.ceph.com" and $p["ceph-rbd-retain"] == "rbd.csi.ceph.com" and $p["cephfs"] == "cephfs.csi.ceph.com"'
check_cmd "ceph-rbd seule classe par défaut ; ceph-rbd-retain en Retain ; ceph-rbd extensible" _m16x_q "$_m16_e46_sc" '
  ([.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] == ["ceph-rbd"])
  and any(.items[]; .metadata.name == "ceph-rbd-retain" and .reclaimPolicy == "Retain")
  and any(.items[]; .metadata.name == "ceph-rbd" and (.allowVolumeExpansion // false))'
check_cmd "aucune classe d'un autre pilote (Rook, Longhorn) ne subsiste" _m16x_q "$_m16_e46_sc" \
  'all(.items[]; .provisioner | test("rook|longhorn|ceph.rook.io|driver.longhorn.io") | not)'
check_cmd "classes d'instantanés ceph-rbd-snap et cephfs-snap" _m16x_q "$(_m16x_j volumesnapshotclasses)" \
  '([.items[].metadata.name] | index("ceph-rbd-snap") and index("cephfs-snap"))'
check_cmd "snapshot-controller disponible" _m16x_deploiement_pret kube-system snapshot-controller
check_cmd "ceph-csi RBD : provisioner disponible" _m16x_deploiement_pret "$_m16x_ns_csi" ceph-csi-rbd-provisioner
check_cmd "ceph-csi CephFS : provisioner disponible" _m16x_deploiement_pret "$_m16x_ns_csi" ceph-csi-cephfs-provisioner
check_cmd "ceph-csi RBD : nodeplugin sur chaque travailleur" _m16x_ds_complet "$_m16x_ns_csi" ceph-csi-rbd-nodeplugin
check_cmd "ceph-csi CephFS : nodeplugin sur chaque travailleur" _m16x_ds_complet "$_m16x_ns_csi" ceph-csi-cephfs-nodeplugin
for _m16_e46_n in "${_m16x_travailleurs[@]}"; do
  _m16_e46_a="${_m16_e46_ip[$_m16_e46_n]:-}"
  [[ -n "$_m16_e46_a" ]] || continue
  check_ssh_output "$_m16_e46_n : adresse $_m16_e46_a/24 sur le VLAN 30, MTU 9000" "$_m16_e46_n" '^OK$' \
    "i=\$(ip -o -4 addr show | awk '\$4 == \"$_m16_e46_a/24\" { print \$2 }'); [ -n \"\$i\" ] && ip link show \"\$i\" | grep -q 'mtu 9000' && echo OK"
  check_ssh "$_m16_e46_n : trames de 9000 octets sans fragmentation vers ceph01 (10.10.30.51)" "$_m16_e46_n" \
    "ping -c 2 -W 2 -M do -s 8972 10.10.30.51"
done

# --- 2. Rien de provisoire -----------------------------------------------------------------------
title "2/8 Rien de provisoire (Rook, Longhorn, disques, pannes)"
_m16_e46_ns="$(_m16x_j namespaces)"
check_cmd "espaces rook-ceph et longhorn-system supprimés" _m16x_q "$_m16_e46_ns" \
  '[.items[].metadata.name] | (index("rook-ceph") or index("longhorn-system")) | not'
check_cmd "aucune CRD de Rook ni de Longhorn" _m16x_q "$(_m16x_j crd)" \
  'all(.items[]; .spec.group | test("(^|\\.)ceph\\.rook\\.io$|(^|\\.)longhorn\\.io$") | not)'
for _m16_e46_n in "${_m16x_travailleurs[@]}"; do
  _m16_e46_v="${_m16_e46_vmid[$_m16_e46_n]:-}"
  [[ -n "$_m16_e46_v" ]] || continue
  check_ssh "VM $_m16_e46_v ($_m16_e46_n) : aucun disque sur ssd-lab ni hdd-bulk (disques de Rook et Longhorn retirés)" \
    "$WB_PVE_HOST" "qm config $_m16_e46_v >/dev/null && ! qm config $_m16_e46_v | grep -Eq '^(scsi|virtio|sata)[0-9]+: (${WB_STORAGE_SSD:-ssd-lab}|${WB_STORAGE_BULK:-hdd-bulk}):'"
  check_ssh "$_m16_e46_n : /var/lib/rook absent, /var/lib/longhorn ni monté ni dans fstab" "$_m16_e46_n" \
    "! test -e /var/lib/rook && ! findmnt -n /var/lib/longhorn >/dev/null && ! grep -q '/var/lib/longhorn' /etc/fstab"
done
check_cmd "aucune panne M16 active (lab/bin/break 16 XX --annuler)" _m16x_aucune_panne_active

# --- 3. Base de données ----------------------------------------------------------------------------
title "3/8 mediagenda-db (CloudNativePG)"
_m16_e46_c="$(_m16x_cnpg)"
check_cmd "mediagenda-db : 3 instances prêtes, phase saine" _m16x_q "$_m16_e46_c" \
  '.spec.instances == 3 and .status.readyInstances == 3 and .status.phase == "Cluster in healthy state"'
check_cmd "mediagenda-db : PostgreSQL 18, volumes sur ceph-rbd" _m16x_q "$_m16_e46_c" \
  '((.status.image // .spec.imageName // "") | test(":18[.-]")) and .spec.storage.storageClass == "ceph-rbd"'
check_cmd "mediagenda-db : WAL archivés par le plugin Barman Cloud (cnpg-s3), archivage en fonctionnement" _m16x_q "$_m16_e46_c" \
  'any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and (.isWALArchiver // false) and .parameters.barmanObjectName == "cnpg-s3")
   and any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")
   and (.spec.backup.barmanObjectStore == null)'
check_cmd "ObjectStore cnpg-s3 : compartiment cnpg-k8s-par1 sur s3-01" _m16x_q \
  "$(_m16x_j objectstores.barmancloud.cnpg.io cnpg-s3 -n "$_m16x_ns_db")" \
  '(.spec.configuration.destinationPath | test("^s3://cnpg-k8s-par1(/|$)")) and (.spec.configuration.endpointURL | contains("s3-01.par1.medisphere.internal:8333"))'
check_cmd "sauvegarde de base planifiée (ScheduledBackup de mediagenda-db)" _m16x_q \
  "$(_m16x_j scheduledbackups.postgresql.cnpg.io -n "$_m16x_ns_db")" \
  'any(.items[]; .spec.cluster.name == "mediagenda-db" and ((.spec.suspend // false) | not))'
check_cmd "une sauvegarde de base terminée il y a moins de 26 h" _m16x_cree_apres \
  "$(_m16x_j backups.postgresql.cnpg.io -n "$_m16x_ns_db")" "$((_m16_e46_now - 93600))" \
  '.spec.cluster.name == "mediagenda-db" and .status.phase == "completed"'

# --- 4. Applications ------------------------------------------------------------------------------
title "4/8 MédiAgenda, Valkey et MédiDoc"
_m16_e46_dep="$(_m16x_j deployments -A)"
check_cmd "MédiAgenda (mediagenda-recette) : toutes ses répliques disponibles" _m16x_q "$_m16_e46_dep" '
  any(.items[]; .metadata.namespace == "mediagenda-recette"
      and any(.spec.template.spec.containers[]; .image | contains("mediagenda-api"))
      and (.status.availableReplicas // 0) >= (.spec.replicas // 1) and (.spec.replicas // 1) >= 2)'
check_cmd "MédiAgenda : MEDIAGENDA_DB_URL lue dans le Secret mediagenda-db-app (CloudNativePG)" _m16x_q "$_m16_e46_dep" '
  any(.items[] | select(.metadata.namespace == "mediagenda-recette") | .spec.template.spec.containers[]
      | select(.image | contains("mediagenda-api")) | .env[]?;
      .name == "MEDIAGENDA_DB_URL" and .valueFrom.secretKeyRef.name == "mediagenda-db-app")'
check_cmd "Valkey (mediagenda-recette) : StatefulSet prêt, volume sur ceph-rbd" _m16x_q \
  "$(_m16x_j statefulsets -n "$_m16x_ns_db")" '
  any(.items[]; (.metadata.name | test("valkey")) and (.status.readyReplicas // 0) >= 1
      and any(.spec.volumeClaimTemplates[]?; (.spec.storageClassName // "ceph-rbd") == "ceph-rbd"))'
check_http "MédiAgenda publiée : https://mediagenda-recette.apps.par1.medisphere.internal/pret" \
  "https://mediagenda-recette.apps.par1.medisphere.internal/pret" 200
check_cmd "MédiDoc : disponible, documents sur RGW (rgw.par1.medisphere.internal), clés S3 lues dans un Secret" \
  _m16x_q "$_m16_e46_dep" '
  any(.items[]; any(.spec.template.spec.containers[]; .image | contains("medidoc"))
      and (.status.availableReplicas // 0) >= 1
      and any(.spec.template.spec.containers[].env[]?; .name == "MEDIDOC_S3_ENDPOINT" and (.value // "" | contains("rgw.par1.medisphere.internal")))
      and any(.spec.template.spec.containers[].env[]?; .name == "MEDIDOC_S3_BUCKET" and (.value // "") == "medidoc-documents")
      and all(.spec.template.spec.containers[].env[]? | select(.name | test("^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)$")); .valueFrom.secretKeyRef != null))'

# --- 5. Velero ---------------------------------------------------------------------------------------
title "5/8 Velero"
check_cmd "emplacement de sauvegarde Available vers velero-k8s-par1" _m16x_q "$(_m16x_j backupstoragelocations.velero.io -n velero)" \
  'any(.items[]; .spec.objectStorage.bucket == "velero-k8s-par1" and .status.phase == "Available")'
check_cmd "node-agent sur chaque travailleur" _m16x_ds_complet velero node-agent
_m16_e46_sch="$(_m16x_j schedules.velero.io -n velero)"
check_cmd "sauvegarde planifiée couvrant mediagenda-recette et medidoc-dev (Schedule actif)" _m16x_q "$_m16_e46_sch" '
  any(.items[]; ((.spec.paused // false) | not) and
      (((.spec.template.includedNamespaces // []) | length == 0) or ((.spec.template.includedNamespaces // []) | index("*"))
       or ((.spec.template.includedNamespaces // []) | (index("mediagenda-recette") and index("medidoc-dev")))))'
check_cmd "dernière sauvegarde planifiée terminée (Completed) il y a moins de 26 h" _m16x_cree_apres \
  "$(_m16x_j backups.velero.io -n velero)" "$((_m16_e46_now - 93600))" \
  '(.metadata.labels["velero.io/schedule-name"] // "") != "" and .status.phase == "Completed"'
check_cmd "test de restauration Velero réussi il y a moins de 30 jours (Restore Completed)" _m16x_cree_apres \
  "$(_m16x_j restores.velero.io -n velero)" "$((_m16_e46_now - 2592000))" '.status.phase == "Completed"'

# --- 6. ceph-par1 (consommateur Kubernetes) -------------------------------------------------------
title "6/8 ceph-par1 : client.k8s et pool k8s-rbd"
_m16_e46_caps="$(_m16x_caps_k8s)"
if [[ -n "$_m16_e46_caps" ]]; then
  check_cmd "client.k8s : profils rbd sur k8s-rbd (mon, osd, mgr), aucun « allow * »" _m16x_q "$_m16_e46_caps" '
    (.mon // "" | contains("profile rbd")) and (.osd // "" | contains("profile rbd pool=k8s-rbd"))
    and (.mgr // "" | contains("profile rbd pool=k8s-rbd")) and ([.[]] | all(.[]; contains("allow *") | not))'
  check_cmd "pool k8s-rbd : ni plein ni presque plein, quota avec marge" _m16x_pool_sain
else
  skip "client.k8s et pool k8s-rbd" "ceph-par1 ne répond pas depuis $_m16x_admin"
fi

# --- 7. Documentation ------------------------------------------------------------------------------------
title "7/8 Documentation (plateforme/medisphere, main)"
check_cmd "ADR-0160 (stockage de k8s-par1) publié sous docs/kubernetes/" _m16x_doc_prefixe docs/kubernetes ADR-0160
check_cmd "politique de sauvegarde : docs/kubernetes/stockage/politique-sauvegarde.md (RPO, RTO)" \
  _m16x_doc_main docs/kubernetes/stockage/politique-sauvegarde.md 'RPO' 'RTO' 'velero' 'cnpg|cloudnativepg|postgres'
for _m16_e46_rb in RB-160 RB-161 RB-162; do
  check_cmd "runbook $_m16_e46_rb publié sous docs/kubernetes/" _m16x_doc_prefixe docs/kubernetes "$_m16_e46_rb"
done
check_cmd "procès-verbal de recette docs/kubernetes/stockage/recette-k8s-stockage-v1.md (restaurations chronométrées)" \
  _m16x_doc_main docs/kubernetes/stockage/recette-k8s-stockage-v1.md 'restaur' 'RTO' 'RPO' '20[0-9]{2}-[01][0-9]-[0-3][0-9]'
check_cmd "matrice des flux : carte VLAN 30 des travailleurs et flux S3 de Velero et CloudNativePG" \
  _m16x_doc_main docs/socle/matrice-flux.md '10\.10\.30\.8[1-3]|10\.10\.30\.81-83' '8333'
_m16_e46_depot="${WB_DEPOT:-$HOME/medisphere}"
if [[ -d "$_m16_e46_depot/docs/kubernetes" ]]; then
  check_cmd "aucune clé cephx ni clé secrète S3 en clair dans docs/kubernetes (clone local)" bash -c \
    '! grep -rEq "AQ[A-Za-z0-9+/]{38}==|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+]{20,}" "$1"' _ "$_m16_e46_depot/docs/kubernetes"
else
  skip "recherche de secrets dans la documentation" "clone local $_m16_e46_depot/docs/kubernetes absent"
fi

# --- 8. Livraison ------------------------------------------------------------------------------------
title "8/8 Livraison"
_m16_e46_etiquette() { gitlab_api "projects/plateforme%2Fmedisphere/repository/tags/k8s-stockage-v1" >/dev/null; }
_m16_e46_pipeline() {
  gitlab_api "projects/plateforme%2Fk8s/pipelines?ref=main&per_page=1" | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}
check_cmd "étiquette k8s-stockage-v1 posée sur plateforme/medisphere" _m16_e46_etiquette
check_cmd "dernier pipeline de main de plateforme/k8s réussi" _m16_e46_pipeline
