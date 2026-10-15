# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E17.sh — M16-E17 : Velero : volumes, Kopia et snapshots CSI
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), registre des secrets local, API GitLab en GET.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E17 — Velero : volumes, Kopia et snapshots CSI"
require_cmd jq kubectl curl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "registre des secrets : mot de passe des dépôts Kopia" _m16o_registre 'kopia'
check_cmd "outils/secrets-sauvegarde.sh (main de plateforme/k8s) gère velero-kopia" \
  grep -q 'velero-kopia' <<<"$(_m16o_contenu_main "$_M16O_PROJET_K8S" outils/secrets-sauvegarde.sh)"
_m16o_vsc="$(_m16o_kj get volumesnapshotclasses.snapshot.storage.k8s.io)"
check_cmd "ceph-rbd-snap et cephfs-snap étiquetées pour Velero, une seule classe étiquetée par pilote" _m16o_json "$_m16o_vsc" '
  [.items[] | select(.metadata.labels["velero.io/csi-volumesnapshot-class"] == "true")] as $e
  | ([$e[].metadata.name] | index("ceph-rbd-snap") != null and index("cephfs-snap") != null)
    and ([$e[].driver] | length == (unique | length))'
_m16o_bk="$(_m16o_kj get backups.velero.io -n velero)"
for _m16o_b in vol-fs vol-dm; do
  check_cmd "sauvegarde $_m16o_b Completed" _m16o_json "$_m16o_bk" \
    'any(.items[]; .metadata.name == $n and .status.phase == "Completed")' --arg n "$_m16o_b"
done
check_cmd "vol-fs : au moins deux PodVolumeBackup terminés" \
  _m16o_json "$(_m16o_kj get podvolumebackups.velero.io -n velero -l velero.io/backup-name=vol-fs)" \
  '[.items[] | select(.status.phase == "Completed")] | length >= 2'
check_cmd "vol-dm : au moins deux DataUpload terminés" \
  _m16o_json "$(_m16o_kj get datauploads.velero.io -n velero -l velero.io/backup-name=vol-dm)" \
  '[.items[] | select(.status.phase == "Completed")] | length >= 2'
check_cmd "au moins une DataDownload ou un PodVolumeRestore terminé" bash -c '
  jq -e "any(.items[]; .status.phase == \"Completed\")" <<<"$1" >/dev/null 2>&1 ||
  jq -e "any(.items[]; .status.phase == \"Completed\")" <<<"$2" >/dev/null 2>&1' \
  _ "$(_m16o_kj get datadownloads.velero.io -n velero)" "$(_m16o_kj get podvolumerestores.velero.io -n velero)"
check_cmd "vol-essai restauré tourne (1 réplica prêt)" \
  _m16o_json "$(_m16o_kj get statefulset vol-essai -n wb-essais)" '(.status.readyReplicas // 0) == 1'
check_cmd "journal : deux vérifications sha256sum réussies et les durées" \
  _m16o_journal_tout E17 10 'sha256sum' '(OK|tout est OK)' '([0-9]+ ?(s|min)|[0-9]+m[0-9]+s)'
check_cmd "mediagenda-dev-quotidienne envoie les volumes hors de Ceph" \
  _m16o_json "$(_m16o_kj get schedules.velero.io mediagenda-dev-quotidienne -n velero)" \
  '.spec.template.snapshotMoveData == true or .spec.template.defaultVolumesToFsBackup == true'
