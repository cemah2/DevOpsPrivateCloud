# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M18-E21 « Panne : la machine reste en Provisioning »
# Lecture seule : objets Cluster API et IPAM de capi-essai (k3s01), jeton, pool et rôle Proxmox lus sur
# pve01 (pveum … list, pvesh get), documentation sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E21 — Les machines de capi-essai aboutissent"
require_cmd kubectl jq ssh
_e21_ns="$_M18P_ESPACE_CAPI"

check_cmd "le cluster de gestion k3s01 répond (readyz)" _m18p_joignable "$_M18P_KC_GESTION"
_e21_m="$(_m18p_gjson get machines.v1beta2.cluster.x-k8s.io -n "$_e21_ns" -l cluster.x-k8s.io/cluster-name=capi-essai)"
check_cmd "toutes les machines de capi-essai sont Running" _m18p_jq "$_e21_m" \
  '(.items | length) >= 3 and all(.items[]; .status.phase == "Running")'
_e21_md="$(_m18p_gjson get machinedeployments.v1beta2.cluster.x-k8s.io -n "$_e21_ns")"
check_cmd "MachineDeployment : tous les réplicas demandés sont prêts" _m18p_jq "$_e21_md" \
  '[.items[]? | select(.spec.clusterName == "capi-essai")] | length >= 1 and all(.[]; .status.readyReplicas == .spec.replicas and .spec.replicas >= 2)'

title "Proxmox (pve01)"
_e21_jeton="$(_m18p_pve 'pveum user token list wb-capi@pve --output-format json')" || _e21_jeton=""
check_cmd "jeton wb-capi@pve!capi présent, sans expiration passée" _m18p_jq "${_e21_jeton:-null}" \
  "any(.[]; .tokenid == \"capi\" and ((.expire // 0) == 0 or (.expire // 0) > $(date +%s)))"
_e21_pmt="$(jq -r '[.items[]? | select(.spec.clusterName == "capi-essai")][0].spec.template.spec.infrastructureRef.name // empty' <<<"$_e21_md" 2>/dev/null)" || _e21_pmt=""
_e21_tpl="$(_m18p_g get proxmoxmachinetemplates.v1alpha2.infrastructure.cluster.x-k8s.io "$_e21_pmt" -n "$_e21_ns" \
  -o jsonpath='{.spec.template.spec.templateID}')" || _e21_tpl=""
if [[ "$_e21_tpl" =~ ^[0-9]+$ ]]; then
  _e21_pool="$(_m18p_pve 'pvesh get /pools --poolid lab --output-format json')" || _e21_pool=""
  check_cmd "le template $_e21_tpl des travailleurs est dans le pool lab" _m18p_jq "${_e21_pool:-null}" \
    "[.[]? | .members[]? | .vmid] | index($_e21_tpl) != null"
else
  skip "template des travailleurs dans le pool lab" "gabarit sans templateID (sélection par étiquettes)"
fi
# Privilèges qu'aucun fournisseur Cluster API n'a à détenir : leur présence trahit un « élargissement ».
_e21_role="$(_m18p_pve 'pveum role list --output-format json')" || _e21_role=""
check_cmd "rôle WBCapi présent, sans privilège d'administration (Permissions, User, Realm, Sys.Modify, Sys.Console)" \
  _m18p_jq "${_e21_role:-null}" '
  [.[]? | select(.roleid == "WBCapi")] | length == 1 and all(.[]; (.privs | split(",")) as $p
    | ($p | map(select(test("^(Permissions\\.Modify|User\\.Modify|Realm\\.|Group\\.Allocate|Sys\\.Modify|Sys\\.Console)"))) | length) == 0)'

title "Adresses (IPAM in-cluster)"
_e21_pc="$(_m18p_g get proxmoxclusters.v1alpha2.infrastructure.cluster.x-k8s.io capi-essai -n "$_e21_ns" \
  -o jsonpath='{.status.inClusterIPPoolRef[0].name}')" || _e21_pc=""
_e21_ipp="$(_m18p_gjson get inclusterippools.ipam.cluster.x-k8s.io "${_e21_pc:-capi-essai-v4-icip}" -n "$_e21_ns")"
check_cmd "pool ${_e21_pc:-capi-essai-v4-icip} : au moins deux adresses libres" _m18p_jq "$_e21_ipp" '(.status.ipAddresses.free // 0) >= 2'
_e21_cl="$(_m18p_gjson get ipaddressclaims.ipam.cluster.x-k8s.io -n "$_e21_ns")"
check_cmd "aucune réservation d'adresse sans propriétaire Cluster API dans $_e21_ns" _m18p_jq "$_e21_cl" \
  '[.items[]? | select((.metadata.ownerReferences // []) | length == 0)] | length == 0'

title "Documentation"
check_cmd "RB-180 publié (phases et raisons, jeton, droits, adresses, point d'accès, pause)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-180 'Provisioning' 'VirtualMachineProvisioned' 'jeton|token' 'IPAddressClaim|adresse' 'paused|pause'
check_cmd "journal de diagnostic INC-4521 publié dans docs/socle/journal/" \
  _m18p_un_fichier_contient plateforme/medisphere docs/socle/journal 'INC-4521'
