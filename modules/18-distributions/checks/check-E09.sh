# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E09.sh — M18-E09 : une image de nœud pour Cluster API
# À lancer depuis adm01. Lecture seule : qm config et ressources du cluster sur pve01, GitLab en GET.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E09 — Une image de nœud pour Cluster API"
require_cmd jq

_m18d_e09_conf="$(_m18d_qm 9060)"
check_cmd "Template 9060 « tpl-capi-ubuntu2404-k136 »" bash -c \
  'grep -qx "name: tpl-capi-ubuntu2404-k136" <<<"$1" && grep -qx "template: 1" <<<"$1"' _ "$_m18d_e09_conf"
check_cmd "Template 9060 : agent activé, disque sur local-nvme en format brut" bash -c \
  'grep -q "^agent: .*1" <<<"$1" && grep -Eq "^scsi0: local-nvme:" <<<"$1" && ! grep -Eq "^scsi0: .*\.qcow2" <<<"$1"' _ "$_m18d_e09_conf"
check_cmd "Template 9060 : étiquettes capi, current, k8s-v1.36.4" _m18d_etiquettes "$_m18d_e09_conf" capi current 'k8s-v1\.36\.4'
check_cmd "Template 9060 dans le pool lab" _m18d_dans_pool 9060
_m18d_e09_vms="$(_m18o_pve '/cluster/resources --type vm')"
check_cmd "Un seul template étiqueté capi et current" _m18d_json "$_m18d_e09_vms" \
  '[.[] | select((.template // 0) == 1 and ((.tags // "") | split(";") | (index("capi") and index("current"))))] | length == 1'
check_cmd "Aucune VM de build ni d'essai restante (pas de 5188, pas de VM ubuntu-2404 hors template)" _m18d_json "$_m18d_e09_vms" \
  '(.[0] != null) and ([.[] | select(.vmid == 5188 or (((.template // 0) == 0) and ((.name // "") | test("^ubuntu-2404"))))] | length == 0)'

_m18d_e09_vars="$(_m18d_contenu_main plateforme/images capi/ubuntu-2404-k136.json)"
check_cmd "plateforme/images (main) : capi/ubuntu-2404-k136.json (VMID 9060, nom, Kubernetes 1.36.4, disque brut)" bash -c \
  'jq -e ".vmid == \"9060\" and .artifact_name == \"tpl-capi-ubuntu2404-k136\" and .kubernetes_semver == \"v1.36.4\" and .kubernetes_deb_version == \"1.36.4-1.1\" and .disk_format == \"raw\"" <<<"$1" >/dev/null' \
  _ "$_m18d_e09_vars"
check_output "plateforme/images (main) : capi/construire.sh remet la vérification TLS" 'insecure_skip_tls_verify *= *false' \
  _m18d_contenu_main plateforme/images capi/construire.sh
_m18d_fichiers_main plateforme/medisphere docs/kubernetes/distributions/image-noeud.md
