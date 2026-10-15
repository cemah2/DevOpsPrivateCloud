# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E21.sh — M16-E21 : Revue : les manifestes stateful du stagiaire
# À lancer depuis adm01. Lecture seule : fichiers corrigés de ~/m16/e21/corrige/ (yq, jq), aucun accès au lab.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E21 — Revue : les manifestes stateful du stagiaire"
require_cmd jq yq

_m16o_d="$_M16O_TRAVAIL/e21"
_m16o_c="$_m16o_d/corrige"
# _m16o_j FICHIER — le fichier corrigé en JSON (tableau de documents), [] s'il est absent.
_m16o_j() {
  if [[ -f "$_m16o_c/$1" ]]; then yq -o=json -I=0 '.' "$_m16o_c/$1" 2>/dev/null | jq -s '[.[] | select(. != null)]' 2>/dev/null || echo '"illisible"'
  else echo '[]'; fi
}
# _m16o_regle FICHIER FILTRE — OK si FILTRE est vrai sur le tableau des documents (vrai si absent quand FILTRE le permet).
_m16o_regle() { jq -e "$2" <<<"$(_m16o_j "$1")" >/dev/null 2>&1; }

check_cmd "fichier $HOME/m16/e21/revue.md : au moins 12 défauts dans le tableau" \
  bash -c '(( $(grep -cE "^\|[[:space:]]*[0-9]+[[:space:]]*\|" "$1" 2>/dev/null || echo 0) >= 12 ))' _ "$_m16o_d/revue.md"
check_cmd "le dossier ~/m16/e21/corrige/ existe" test -d "$_m16o_c"
check_cmd "00-storageclass (si gardé) : pas par défaut, pas de journaling, aucune identité d'administration" _m16o_regle 00-storageclass.yaml '
  type == "array" and all(.[]; (.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false") != "true"
    and ((.parameters.imageFeatures // "") | test("journaling") | not)
    and ([.parameters // {} | to_entries[] | select(.key | test("secret-name$")) | .value | test("admin")] | any | not))'
check_cmd "10-secrets : aucun Secret avec des données dans le dépôt" _m16o_regle 10-secrets.yaml \
  'type == "array" and all(.[]; .kind != "Secret" or ((.data // {}) + (.stringData // {}) | length) == 0)'
check_cmd "20-pvc-partage : un PVC RWX est sur cephfs (pas de RWX sur RBD en mode fichier)" _m16o_regle 20-pvc-partage.yaml '
  type == "array" and length >= 1 and all(.[] | select(.kind == "PersistentVolumeClaim");
    ((.spec.accessModes | index("ReadWriteMany")) == null) or .spec.storageClassName == "cephfs" or .spec.volumeMode == "Block")'
check_cmd "30-postgres-maison (si gardé) : volumes par instance, rétention Retain, ni hostPath ni :latest" _m16o_regle 30-postgres-maison.yaml '
  type == "array" and all(.[] | select(.kind == "StatefulSet");
    ((.spec.volumeClaimTemplates // []) | length) >= 1
    and ((.spec.persistentVolumeClaimRetentionPolicy.whenDeleted // "Retain") == "Retain")
    and ([.spec.template.spec.volumes[]? | select(.hostPath)] | length == 0)
    and all(.spec.template.spec.containers[]; (.image | test(":latest$|^[^:]+$") | not)))'
check_cmd "40-cnpg-cluster : plugin Barman Cloud, sans barmanObjectStore, anti-affinité, image de Harbor" _m16o_regle 40-cnpg-cluster.yaml '
  type == "array" and any(.[]; .kind == "Cluster"
    and .spec.backup.barmanObjectStore == null
    and any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and .isWALArchiver == true)
    and (.spec.affinity.enablePodAntiAffinity // true) == true
    and (.spec.imageName // "" | startswith("registry.par1.medisphere.internal/")))'
check_cmd "50-objectstore : HTTPS avec CA, serverName vide, chemin distinct de celui de MédiAgenda, rétention" _m16o_regle 50-objectstore.yaml '
  type == "array" and any(.[]; .kind == "ObjectStore"
    and (.spec.configuration.endpointURL | startswith("https://")) and (.spec.configuration.endpointCA.name // "") != ""
    and ((.spec.configuration.serverName // "") == "")
    and (.spec.configuration.destinationPath | rtrimstr("/")) != "s3://cnpg-k8s-par1"
    and (.spec.retentionPolicy // "") != "")'
check_cmd "60-scheduledbackup : six champs, méthode plugin" _m16o_regle 60-scheduledbackup.yaml '
  type == "array" and any(.[]; .kind == "ScheduledBackup"
    and (.spec.schedule | split(" ") | map(select(. != "")) | length) == 6
    and .spec.method == "plugin" and .spec.pluginConfiguration.name == "barman-cloud.cloudnative-pg.io")'
check_cmd "70-velero-schedule : medidoc-dev seulement, données déplacées hors de Ceph, pas de copie à chaud de la base" _m16o_regle 70-velero-schedule.yaml '
  type == "array" and any(.[]; .kind == "Schedule"
    and (.spec.template.includedNamespaces == ["medidoc-dev"])
    and .spec.template.snapshotMoveData == true and (.spec.template.defaultVolumesToFsBackup // false) == false)'
_m16o_tout_sans_cle() { local f; for f in "$_m16o_c"/*.yaml; do [[ -f "$f" ]] || continue; _m16o_sans_cle "$(cat "$f")" || return 1; done; }
check_cmd "aucun motif de clé dans les fichiers corrigés" _m16o_tout_sans_cle
