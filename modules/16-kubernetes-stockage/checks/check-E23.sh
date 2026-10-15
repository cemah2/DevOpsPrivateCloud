# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E23.sh — M16-E23 : Le stockage du cluster décrit par le code
# À lancer depuis adm01. Lecture seule : API GitLab en GET, objets Kubernetes (wb-checks), journal local.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E23 — Le stockage du cluster décrit par le code"
require_cmd jq yq kubectl curl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
_m16o_fichiers=(
  composants/ceph-csi/values-rbd.yaml composants/ceph-csi/values-cephfs.yaml composants/ceph-csi/installer.sh
  composants/snapshot-controller/kustomization.yaml
  composants/ceph-csi/classes/ceph-rbd.yaml composants/ceph-csi/classes/ceph-rbd-retain.yaml
  composants/ceph-csi/classes/cephfs.yaml composants/ceph-csi/classes/ceph-rbd-snap.yaml composants/ceph-csi/classes/cephfs-snap.yaml
  composants/velero/values.yaml composants/velero/planifications.yaml
  composants/cloudnative-pg/values.yaml composants/plugin-barman-cloud/values.yaml
  admission/classes-stockage.yaml espaces/mediagenda-dev/30-quota-stockage.yaml espaces/mediagenda-recette/30-quota-stockage.yaml
  espaces/mediagenda-recette/50-mediagenda-db.yaml espaces/mediagenda-recette/60-cnpg-s3.yaml
  espaces/mediagenda-recette/70-mediagenda-db-sauvegarde.yaml
  outils/ceph-csi-secrets.sh outils/secrets-sauvegarde.sh docs/stockage.md Taskfile.yml
)
_m16o_manque=""; _m16o_cles=""
for _m16o_f in "${_m16o_fichiers[@]}"; do
  _m16o_x="$(_m16o_contenu_main "$_M16O_PROJET_K8S" "$_m16o_f")"
  if [[ -z "$_m16o_x" ]]; then _m16o_manque+=" $_m16o_f"; elif ! _m16o_sans_cle "$_m16o_x"; then _m16o_cles+=" $_m16o_f"; fi
done
check_cmd "fichiers attendus sur main de plateforme/k8s (manquants :${_m16o_manque:- aucun})" test -z "$_m16o_manque"
check_cmd "aucun motif de clé dans ces fichiers (en cause :${_m16o_cles:- aucun})" test -z "$_m16o_cles"
_m16o_sans_essais() { _m16o_dossier_absent_main "$_M16O_PROJET_K8S" composants/rook && _m16o_dossier_absent_main "$_M16O_PROJET_K8S" composants/longhorn; }
check_cmd "composants/rook/ et composants/longhorn/ absents de main" _m16o_sans_essais
check_cmd "task stockage:appliquer définie dans Taskfile.yml" grep -q 'stockage:appliquer' <<<"$(_m16o_contenu_main "$_M16O_PROJET_K8S" Taskfile.yml)"

# Classes : mêmes paramètres dans le cluster et dans le dépôt.
_m16o_meme_classe() { # FICHIER RESSOURCE NOM CHAMPS_JQ
  local depot cluster
  # -S : l'API renvoie les clés des tables (parameters) triées ; le fichier, dans son ordre à lui.
  depot="$(_m16o_contenu_main "$_M16O_PROJET_K8S" "$1" | yq -o=json -I=0 'select(.metadata.name == "'"$3"'")' 2>/dev/null | jq -cS "$4" 2>/dev/null)"
  cluster="$(_m16o_kj get "$2" "$3" | jq -cS "$4" 2>/dev/null)"
  [[ -n "$depot" && "$depot" == "$cluster" ]]
}
for _m16o_c in ceph-rbd ceph-rbd-retain cephfs; do
  check_cmd "StorageClass $_m16o_c identique au dépôt (pilote, paramètres, récupération, agrandissement)" \
    _m16o_meme_classe "composants/ceph-csi/classes/$_m16o_c.yaml" storageclass "$_m16o_c" \
    '{provisioner, parameters, reclaimPolicy, allowVolumeExpansion, volumeBindingMode}'
done
for _m16o_c in ceph-rbd-snap cephfs-snap; do
  check_cmd "VolumeSnapshotClass $_m16o_c identique au dépôt" \
    _m16o_meme_classe "composants/ceph-csi/classes/$_m16o_c.yaml" volumesnapshotclasses.snapshot.storage.k8s.io "$_m16o_c" \
    '{driver, parameters, deletionPolicy}'
done
# Images déployées = valeurs du dépôt.
_m16o_tag_depot() { _m16o_contenu_main "$_M16O_PROJET_K8S" "$1" | yq -r '.image.tag // ""' 2>/dev/null | tr -d '"'; }
_m16o_velero_tag="$(_m16o_tag_depot composants/velero/values.yaml)"
check_cmd "image de Velero déployée = image.tag du dépôt (${_m16o_velero_tag:-?})" \
  _m16o_json "$(_m16o_kj get deployment velero -n velero)" \
  '$t != "" and any(.spec.template.spec.containers[]; .name == "velero" and (.image | endswith(":" + $t)))' --arg t "$_m16o_velero_tag"
_m16o_cnpg_tag="$(_m16o_tag_depot composants/cloudnative-pg/values.yaml)"
check_cmd "image de l'opérateur CNPG déployée = image.tag du dépôt (${_m16o_cnpg_tag:-?})" \
  _m16o_json "$(_m16o_kj get deployments -n cnpg-system)" \
  '$t != "" and any(.items[].spec.template.spec.containers[]; .image | test("cloudnative-pg:" + $t + "$"))' --arg t "$_m16o_cnpg_tag"
_m16o_pipeline() {
  local p
  p="$(jq -rn --arg v "$_M16O_PROJET_K8S" '$v | @uri')"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null
}
check_cmd "dernier pipeline de main de plateforme/k8s réussi" _m16o_pipeline
check_cmd "journal : stockage:appliquer rejouée sans changement (preuve de dérive nulle)" \
  _m16o_journal_tout E23 5 'stockage:appliquer|stockage:derive|derive-stockage' '(aucun [ée]cart|unchanged|0 [ée]cart)'
