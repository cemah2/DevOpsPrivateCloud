# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E03.sh — M16-E03 : PV, PVC et StorageClass, le cycle de vie d'un volume
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks), fichier du volume local
# sur k8s-w01 en SSH.

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E03 — PV, PVC et StorageClass : le cycle de vie d'un volume"
require_cmd jq kubectl

_m16d_e03_sc="$(_m16d_sc local-manuel)"
_m16d_e03_pv="$(_m16d_kj get pv e03-local-w01)"
_m16d_e03_pvc="$(_m16d_kj get pvc e03-donnees -n wb-essais)"

# --- 1. La classe -------------------------------------------------------------------------------------
check_cmd "StorageClass local-manuel : aucun provisioner (kubernetes.io/no-provisioner)" \
  _m16d_json "$_m16d_e03_sc" '.provisioner == "kubernetes.io/no-provisioner"'
check_cmd "local-manuel : liaison différée (WaitForFirstConsumer)" \
  _m16d_json "$_m16d_e03_sc" '.volumeBindingMode == "WaitForFirstConsumer"'
check_cmd "local-manuel n'est PAS la classe par défaut" _m16d_json "$_m16d_e03_sc" \
  '(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false") != "true"'

# --- 2. Le PV -----------------------------------------------------------------------------------------
check_cmd "PV e03-local-w01 : local /srv/wb-local/e03, 1Gi, RWO, Filesystem, Retain, classe local-manuel" \
  _m16d_json "$_m16d_e03_pv" '
    .spec.local.path == "/srv/wb-local/e03" and .spec.capacity.storage == "1Gi"
    and .spec.accessModes == ["ReadWriteOnce"] and (.spec.volumeMode // "Filesystem") == "Filesystem"
    and .spec.persistentVolumeReclaimPolicy == "Retain" and .spec.storageClassName == "local-manuel"'
check_cmd "PV e03-local-w01 : affinité de nœud k8s-w01" _m16d_json "$_m16d_e03_pv" '
  [.spec.nodeAffinity.required.nodeSelectorTerms[].matchExpressions[]
   | select(.key == "kubernetes.io/hostname" and .operator == "In") | .values[]] == ["k8s-w01"]'

# --- 3. La liaison, après libération et réutilisation ---------------------------------------------------
check_cmd "PVC wb-essais/e03-donnees lié (Bound) dans local-manuel au PV e03-local-w01" _m16d_json "$_m16d_e03_pvc" '
  .status.phase == "Bound" and .spec.storageClassName == "local-manuel" and .spec.volumeName == "e03-local-w01"'
check_cmd "PV e03-local-w01 lié (Bound) à CE PVC (claimRef : même UID)" \
  bash -c 'u="$(jq -r .metadata.uid <<<"$2")"; [[ -n "$u" && "$u" != null ]] && jq -e --arg u "$u" \
    ".status.phase == \"Bound\" and .spec.claimRef.namespace == \"wb-essais\" and .spec.claimRef.name == \"e03-donnees\" and .spec.claimRef.uid == \$u" <<<"$1" >/dev/null' \
  _ "$_m16d_e03_pv" "$_m16d_e03_pvc"
# Réutilisation : le PVC lié aujourd'hui a été recréé APRÈS le PV (au moins 3 minutes plus tard).
check_cmd "le PVC lié a été recréé après coup (PVC plus récent que le PV d'au moins 3 min)" \
  bash -c 'p="$(jq -r ".metadata.creationTimestamp" <<<"$1")"; c="$(jq -r ".metadata.creationTimestamp" <<<"$2")"
    [[ "$p" != null && "$c" != null ]] && (( $(date -d "$c" +%s) - $(date -d "$p" +%s) >= 180 ))' \
  _ "$_m16d_e03_pv" "$_m16d_e03_pvc"

# --- 4. Les données, avant et après --------------------------------------------------------------------
# trace : « <epoch> <pod> » ; il faut une ligne antérieure ET une postérieure à la création du PVC.
_m16d_e03_t="$(jq -r '.metadata.creationTimestamp // empty' <<<"$_m16d_e03_pvc" 2>/dev/null || true)"
_m16d_e03_t="$( [[ -n "$_m16d_e03_t" ]] && date -d "$_m16d_e03_t" +%s 2>/dev/null || echo 0)"
check_ssh "k8s-w01 : /srv/wb-local/e03/trace a des lignes d'avant ET d'après la réutilisation" k8s-w01 \
  "f=/srv/wb-local/e03/trace; t=$_m16d_e03_t; [ \"\$t\" -gt 0 ] && [ -s \$f ] \
   && awk -v t=\"\$t\" '\$1 ~ /^[0-9]+\$/ { if (\$1 < t) a = 1; else b = 1 } END { exit !(a && b) }' \$f"

# --- 5. Ménage -----------------------------------------------------------------------------------------
check_cmd "plus de PVC e03-partage dans wb-essais" _m16d_absent pvc e03-partage -n wb-essais
check_cmd "plus aucun pod e03-* dans wb-essais" _m16d_json "$(_m16d_kj get pods -n wb-essais)" \
  '[.items[] | select(.metadata.name | startswith("e03-"))] | length == 0'
