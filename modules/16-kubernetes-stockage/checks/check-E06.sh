# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E06.sh — M16-E06 : ceph-csi, des volumes RBD sur ceph-par1
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets),
# commandes « ceph » et « rbd » d'observation sur le nœud _admin, connexions des travailleurs (ss),
# API GitLab en GET.

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E06 — ceph-csi : des volumes RBD sur ceph-par1"
require_cmd jq kubectl curl

_m16d_e06_fsid="$(_m16d_fsid)"
check_cmd "ceph-par1 répond depuis $_M16D_ADMIN (ceph fsid)" \
  bash -c '[[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]' _ "$_m16d_e06_fsid"

# --- 1. Le contrôleur de snapshots ----------------------------------------------------------------------
for _m16d_e06_crd in volumesnapshots volumesnapshotcontents volumesnapshotclasses; do
  check_cmd "CRD $_m16d_e06_crd.snapshot.storage.k8s.io (v1 servie)" \
    _m16d_json "$(_m16d_kj get crd "$_m16d_e06_crd.snapshot.storage.k8s.io")" 'any(.spec.versions[]; .name == "v1" and .served)'
done
check_cmd "kube-system/snapshot-controller disponible, image $_M16D_SNAP_VERSION" \
  _m16d_json "$(_m16d_kj get deployment snapshot-controller -n kube-system)" '
    (.status.availableReplicas // 0) >= 1
    and any(.spec.template.spec.containers[]; .image | endswith(":" + $v))' --arg v "$_M16D_SNAP_VERSION"

# --- 2. Le pilote RBD -----------------------------------------------------------------------------------
check_cmd "espace ceph-csi en Pod Security « privileged »" _m16d_json "$(_m16d_kj get namespace ceph-csi)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "privileged"'
check_cmd "nodeplugin RBD : image cephcsi $_M16D_CSI_VERSION, tous les pods prêts" \
  _m16d_json "$(_m16d_kj get daemonset ceph-csi-rbd-nodeplugin -n ceph-csi)" '
    any(.spec.template.spec.containers[]; .name == "csi-rbdplugin" and (.image | endswith("cephcsi:" + $v)))
    and .status.desiredNumberScheduled > 0 and .status.numberReady == .status.desiredNumberScheduled' \
  --arg v "$_M16D_CSI_VERSION"
check_cmd "nodeplugin RBD : exactement sur les travailleurs ($_M16D_TRAVAILLEURS)" \
  bash -c 'diff <(printf "%s\n" "$1") <(printf "%s\n" "$2") >/dev/null' _ \
  "$(_m16d_noeuds_pods ceph-csi app=ceph-csi-rbd,component=nodeplugin)" "$(_m16d_travailleurs_tries)"
check_cmd "provisioner RBD : 2 réplicas prêts, sur des travailleurs" \
  bash -c '[[ "$(jq -r "(.spec.replicas|tostring) + \"/\" + ((.status.readyReplicas // 0)|tostring)" <<<"$1")" == 2/2 ]] \
    && [[ -n "$2" ]] && ! grep -vxF -f <(printf "%s\n" $3) <<<"$2" >/dev/null' _ \
  "$(_m16d_kj get deployment ceph-csi-rbd-provisioner -n ceph-csi)" \
  "$(_m16d_noeuds_pods ceph-csi app=ceph-csi-rbd,component=provisioner)" "$_M16D_TRAVAILLEURS"
_m16d_e06_conf="$(_m16d_kj get configmap ceph-csi-config -n ceph-csi | jq -r '.data["config.json"] // empty' 2>/dev/null || true)"
check_cmd "configuration du pilote : clusterID = fsid de ceph-par1, moniteurs 10.10.30.51-53 en 3300 seulement" \
  _m16d_json "$_m16d_e06_conf" '
    length == 1 and .[0].clusterID == $f
    and (.[0].monitors | sort) == ["10.10.30.51:3300", "10.10.30.52:3300", "10.10.30.53:3300"]' \
  --arg f "$_m16d_e06_fsid"

# --- 3. Les classes -------------------------------------------------------------------------------------
_m16d_e06_scs="$(_m16d_kj get storageclass)"
check_cmd "ceph-rbd est la SEULE classe par défaut" _m16d_json "$_m16d_e06_scs" '
  [.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] == ["ceph-rbd"]'
for _m16d_e06_c in ceph-rbd:Delete ceph-rbd-retain:Retain; do
  check_cmd "classe ${_m16d_e06_c%%:*} : rbd.csi.ceph.com, pool k8s-rbd, fonctionnalités, ext4, ms_mode=secure, secrets, ${_m16d_e06_c##*:}, agrandissement" \
    _m16d_json "$_m16d_e06_scs" '
      .items[] | select(.metadata.name == $n)
      | .provisioner == "rbd.csi.ceph.com" and .reclaimPolicy == $r and .allowVolumeExpansion == true
        and .parameters.clusterID == $f and .parameters.pool == "k8s-rbd"
        and .parameters.imageFeatures == $feat
        and .parameters["csi.storage.k8s.io/fstype"] == "ext4"
        and (.parameters.mapOptions // "" | test("ms_mode=secure"))
        and .parameters["csi.storage.k8s.io/provisioner-secret-name"] == "csi-rbd-secret"
        and .parameters["csi.storage.k8s.io/node-stage-secret-name"] == "csi-rbd-secret"
        and .parameters["csi.storage.k8s.io/controller-expand-secret-name"] == "csi-rbd-secret"
        and .parameters["csi.storage.k8s.io/node-stage-secret-namespace"] == "ceph-csi"
        and ((.mountOptions // []) | index("discard"))' \
    --arg n "${_m16d_e06_c%%:*}" --arg r "${_m16d_e06_c##*:}" --arg f "$_m16d_e06_fsid" --arg feat "$_M16D_FEATURES"
done

# --- 4. Côté Ceph -----------------------------------------------------------------------------------------
check_cmd "client.k8s : profils rbd sur k8s-rbd (mon, osd, mgr), rien d'autre" \
  _m16d_json "$(_m16d_ceph "auth get client.k8s -f json")" '
    .[0].caps == {"mgr": "profile rbd pool=k8s-rbd", "mon": "profile rbd", "osd": "profile rbd pool=k8s-rbd"}'
check_cmd "pool k8s-rbd : application rbd" _m16d_json "$(_m16d_ceph "osd pool application get k8s-rbd -f json")" 'has("rbd")'

# --- 5. Le volume d'essai, et pas d'image orpheline ------------------------------------------------------
_m16d_e06_pvc="$(_m16d_kj get pvc e06-essai -n wb-essais)"
check_cmd "PVC wb-essais/e06-essai lié dans ceph-rbd" _m16d_json "$_m16d_e06_pvc" \
  '.status.phase == "Bound" and .spec.storageClassName == "ceph-rbd"'
check_cmd "pod wb-essais/e06-essai en marche" _m16d_json "$(_m16d_kj get pod e06-essai -n wb-essais)" \
  '.status.phase == "Running"'
_m16d_e06_pvs="$(_m16d_kj get pv)"
_m16d_e06_images="$(_m16d_rbd "ls k8s-rbd --format json")"
_m16d_e06_img="$(jq -r --arg pv "$(jq -r '.spec.volumeName // empty' <<<"$_m16d_e06_pvc" 2>/dev/null)" \
  '.items[] | select(.metadata.name == $pv) | .spec.csi.volumeAttributes.imageName // empty' <<<"$_m16d_e06_pvs" 2>/dev/null || true)"
check_cmd "l'image du PVC e06-essai (${_m16d_e06_img:-?}) existe dans k8s-rbd" \
  _m16d_json "$_m16d_e06_images" 'index($i) != null' --arg i "$_m16d_e06_img"
check_cmd "aucun PV RBD en Released" _m16d_json "$_m16d_e06_pvs" \
  '[.items[] | select(.spec.csi.driver == "rbd.csi.ceph.com" and .status.phase == "Released")] | length == 0'
# (Les images intermédiaires « …-temp » des clones de PVC, M16-E10, ne sont pas comptées.)
check_cmd "aucune image csi-vol-… de k8s-rbd sans PV" \
  bash -c 'diff <(jq -r ".[] | select(startswith(\"csi-vol-\") and (endswith(\"-temp\") | not))" <<<"$1" | sort) \
    <(jq -r ".items[] | select(.spec.csi.driver == \"rbd.csi.ceph.com\" and .spec.csi.volumeAttributes.pool == \"k8s-rbd\") | .spec.csi.volumeAttributes.imageName" <<<"$2" | sort) \
    | grep -q "^<" && exit 1; [[ -n "$1" ]]' _ "$_m16d_e06_images" "$_m16d_e06_pvs"

# --- 6. Le protocole sur les nœuds ----------------------------------------------------------------------
_m16d_e06_noeud="$(_m16d_kj get pod e06-essai -n wb-essais | jq -r '.spec.nodeName // empty' 2>/dev/null || true)"
check_ssh "${_m16d_e06_noeud:-nœud de e06-essai} : connexions établies vers les moniteurs sur 3300" "${_m16d_e06_noeud:-k8s-w01}" \
  '[ "$(ss -Htn state established "( dst 10.10.30.0/24 and dport = :3300 )" | wc -l)" -ge 1 ]'
for _m16d_e06_n in $_M16D_TRAVAILLEURS; do
  check_ssh "$_m16d_e06_n : aucune connexion vers les moniteurs en msgr1 (6789)" "$_m16d_e06_n" \
    '[ "$(ss -Htn "( dst 10.10.30.0/24 and dport = :6789 )" | wc -l)" = 0 ]'
done

# --- 7. Le code -----------------------------------------------------------------------------------------
check_cmd "plateforme/k8s (main) : secrets/ceph-csi.yml chiffré sous l'identité « critique »" \
  bash -c 'head -n 1 <<<"$1" | grep -q "^\$ANSIBLE_VAULT;1\.2;AES256;critique"' _ \
  "$(_m16d_contenu_main plateforme/k8s secrets/ceph-csi.yml)"
for _m16d_e06_f in espaces/ceph-csi.yaml composants/snapshot-controller/kustomization.yaml \
  composants/ceph-csi/installer.sh composants/ceph-csi/classes/ceph-rbd.yaml \
  composants/ceph-csi/classes/ceph-rbd-retain.yaml outils/ceph-csi-secrets.sh; do
  check_cmd "plateforme/k8s (main) : $_m16d_e06_f" _m16d_fichier_main plateforme/k8s "$_m16d_e06_f"
done
check_cmd "plateforme/k8s (main) : values-rbd.yaml renseigné (fsid du cluster, plus de <FSID>)" \
  bash -c 'grep -q -- "$2" <<<"$1" && ! grep -q "<FSID>" <<<"$1"' _ \
  "$(_m16d_contenu_main plateforme/k8s composants/ceph-csi/values-rbd.yaml)" "${_m16d_e06_fsid:-fsid-introuvable}"
