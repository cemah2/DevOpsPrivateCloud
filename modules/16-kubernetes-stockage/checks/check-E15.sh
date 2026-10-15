# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E15.sh — M16-E15 : Longhorn : du stockage répliqué sur les nœuds
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), nœuds en SSH (findmnt, wipefs -n, systemctl), fichiers locaux.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E15 — Longhorn : du stockage répliqué sur les nœuds"
# Contrôle l'état APRÈS le retrait de Longhorn (étape 8), plus les traces de l'essai dans le journal.
require_cmd jq kubectl ssh

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "l'espace longhorn-system n'existe plus" _m16o_absent namespace longhorn-system
check_cmd "aucune CRD *.longhorn.io ne reste" _m16o_json "$(_m16o_kj get crd)" \
  '[.items[] | select(.metadata.name | endswith(".longhorn.io"))] | length == 0'
check_cmd "aucun CSIDriver driver.longhorn.io" _m16o_absent csidriver driver.longhorn.io
check_cmd "aucune StorageClass, VolumeSnapshotClass ni PV de Longhorn" bash -c '
  jq -e "[.items[] | select(.provisioner == \"driver.longhorn.io\")] | length == 0" <<<"$1" >/dev/null &&
  jq -e "[.items[] | select(.driver == \"driver.longhorn.io\")] | length == 0" <<<"$2" >/dev/null &&
  jq -e "[.items[] | select((.spec.csi.driver // \"\") == \"driver.longhorn.io\")] | length == 0" <<<"$3" >/dev/null' \
  _ "$(_m16o_kj get storageclass)" "$(_m16o_kj get volumesnapshotclasses.snapshot.storage.k8s.io)" "$(_m16o_kj get pv)"
check_cmd "aucun PVC lh-* dans wb-essais" _m16o_json "$(_m16o_kj get pvc -n wb-essais)" \
  '[.items[] | select(.metadata.name | startswith("lh-"))] | length == 0'
check_cmd "ceph-rbd reste la seule classe par défaut" _m16o_defaut_unique
check_cmd "travailleurs : /var/lib/longhorn n'est plus monté" _m16o_sur_travailleurs '! findmnt -n /var/lib/longhorn >/dev/null'
check_cmd "travailleurs : disque <nœud>-lh présent (32 Gio)" _m16o_disque_32g lh
check_cmd "travailleurs : disque <nœud>-lh sans aucune signature" _m16o_disque_vierge lh
check_cmd "travailleurs : iscsid n'est plus actif" _m16o_sur_travailleurs '! systemctl is-active --quiet iscsid'
check_cmd "plus de clé longhorn-essai dans ~/.config/workbook/" test ! -e "$_M16O_CFG/s3-longhorn-essai.env"
check_cmd "journal : reconstruction d'un réplica (états, durée)" _m16o_journal_tout E15 5 'r[ée]plica' '(degraded|d[ée]grad)'
check_cmd "journal : contenu du compartiment après la sauvegarde, et mesures" _m16o_journal_tout E15 5 '(backupstore|longhorn-essai)' '(MB/s|Mo/s|MiB/s|Mio/s)'
