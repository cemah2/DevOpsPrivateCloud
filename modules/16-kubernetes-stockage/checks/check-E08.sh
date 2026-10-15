# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M16-E08 : StatefulSet et volumes par instance
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks), requête HTTPS sur la
# Gateway de recette (CA MédiSphère du système).

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E08 — StatefulSet et volumes par instance"
require_cmd jq kubectl curl

# --- 1. Le patron, dans wb-essais -------------------------------------------------------------------------
_m16d_e08_essai="$(_m16d_kj get statefulset e08-valkey -n wb-essais)"
check_cmd "wb-essais/e08-valkey : 2 réplicas demandés et prêts" _m16d_json "$_m16d_e08_essai" \
  '.spec.replicas == 2 and (.status.readyReplicas // 0) == 2'
check_cmd "e08-valkey : politique whenScaled Delete, whenDeleted Retain" _m16d_json "$_m16d_e08_essai" \
  '.spec.persistentVolumeClaimRetentionPolicy == {"whenDeleted": "Retain", "whenScaled": "Delete"}'
check_cmd "e08-valkey : modèle de volume « donnees » en ceph-rbd" _m16d_json "$_m16d_e08_essai" \
  'any(.spec.volumeClaimTemplates[]; .metadata.name == "donnees" and .spec.storageClassName == "ceph-rbd")'
check_cmd "wb-essais : exactement les PVC donnees-e08-valkey-0 et -1, liés en ceph-rbd" \
  _m16d_json "$(_m16d_kj get pvc -n wb-essais)" '
    [.items[] | select(.metadata.name | startswith("donnees-e08-valkey-"))] as $p
    | ($p | map(.metadata.name) | sort) == ["donnees-e08-valkey-0", "donnees-e08-valkey-1"]
      and all($p[]; .status.phase == "Bound" and .spec.storageClassName == "ceph-rbd")'

# --- 2. Le Valkey de recette -------------------------------------------------------------------------------
_m16d_e08_sts="$(_m16d_kj get statefulset valkey -n mediagenda-recette)"
check_cmd "mediagenda-recette/valkey : StatefulSet d'1 réplica prêt" _m16d_json "$_m16d_e08_sts" \
  '.spec.replicas == 1 and (.status.readyReplicas // 0) == 1'
check_cmd "valkey : image registry.par1.medisphere.internal/dockerhub/valkey/valkey:8.1" \
  _m16d_json "$_m16d_e08_sts" \
  'any(.spec.template.spec.containers[]; .image == "registry.par1.medisphere.internal/dockerhub/valkey/valkey:8.1")'
check_cmd "valkey : persistance AOF activée (--appendonly yes)" _m16d_json "$_m16d_e08_sts" '
  any(.spec.template.spec.containers[]; ((.command // []) + (.args // [])) | join(" ") | test("--appendonly +yes"))'
check_cmd "valkey : profil restricted (non root, utilisateur 999, capacités retirées, seccomp)" \
  _m16d_json "$_m16d_e08_sts" '
    .spec.template.spec as $s
    | ($s.securityContext.runAsNonRoot == true) and ($s.securityContext.runAsUser == 999)
      and (($s.securityContext.seccompProfile.type // "") == "RuntimeDefault")
      and all($s.containers[]; .securityContext.allowPrivilegeEscalation == false
                              and ((.securityContext.capabilities.drop // []) | index("ALL")))'
check_cmd "valkey : politique Retain / Retain et Service sans tête valkey (serviceName, URL de l'API)" \
  bash -c 'jq -e ".spec.persistentVolumeClaimRetentionPolicy // {\"whenDeleted\":\"Retain\",\"whenScaled\":\"Retain\"}
      | . == {\"whenDeleted\":\"Retain\",\"whenScaled\":\"Retain\"}" <<<"$1" >/dev/null \
    && jq -e ".spec.serviceName == \"valkey\"" <<<"$1" >/dev/null \
    && jq -e ".spec.clusterIP == \"None\"" <<<"$2" >/dev/null' _ \
  "$_m16d_e08_sts" "$(_m16d_kj get service valkey -n mediagenda-recette)"
check_cmd "PVC mediagenda-recette/donnees-valkey-0 lié en ceph-rbd" \
  _m16d_json "$(_m16d_kj get pvc donnees-valkey-0 -n mediagenda-recette)" \
  '.status.phase == "Bound" and .spec.storageClassName == "ceph-rbd"'
check_cmd "plus d'autre Valkey (répliques valkey-1/-2, Deployment, pod à volume emptyDir/hostPath) dans mediagenda-recette" \
  bash -c 'jq -e "[.items[] | select(.metadata.name | test(\"valkey\"))] | length == 0" <<<"$1" >/dev/null \
    && jq -e "[.items[] | select(any(.spec.containers[]; .image | test(\"valkey\")))] | map(.metadata.name) == [\"valkey-0\"]" <<<"$2" >/dev/null \
    && jq -e "[.items[] | select(any(.spec.containers[]; .image | test(\"valkey\")))
               | select(any(.spec.volumes[]?; has(\"emptyDir\") or has(\"hostPath\")))] | length == 0" <<<"$2" >/dev/null' _ \
  "$(_m16d_kj get deployments -n mediagenda-recette)" "$(_m16d_kj get pods -n mediagenda-recette)"

# --- 3. L'application -------------------------------------------------------------------------------------
check_http "MédiAgenda (recette) : /pret répond 200 (PostgreSQL et Valkey joignables)" \
  "https://mediagenda-recette.apps.par1.medisphere.internal/pret" 200
