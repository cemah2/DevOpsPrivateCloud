# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E33.sh — M16-E33 « Mettre à jour ceph-csi et CloudNativePG sans interruption »
# Lecture seule : images et état de déploiement des pilotes (espace ceph-csi), de l'opérateur et du
# plugin (cnpg-system), état des Cluster, témoins restants, sonde, documentation (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E33 — Mettre à jour ceph-csi et CloudNativePG sans interruption"
require_cmd jq kubectl curl sort

# _m16_e33_au_moins VERSION MINIMUM PRÉFIXE — VERSION commence par PRÉFIXE et n'est pas inférieure
# à MINIMUM (comparaison de versions de sort -V, préfixe « v » ignoré).
_m16_e33_au_moins() {
  local v="${1#v}" min="${2#v}" pre="$3"
  [[ -n "$v" && "$v" == "$pre"* ]] || return 1
  [[ "$(printf '%s\n%s\n' "$min" "$v" | sort -V | head -n 1)" == "$min" ]]
}

# _m16_e33_tags ESPACE MOTIF — étiquettes (uniques) des images de conteneurs des pods de l'espace
# dont le nom d'image contient MOTIF.
_m16_e33_tags() {
  _m16p_kj pods -n "$1" | jq -r --arg m "$2" \
    '[.items[]?.spec.containers[]?.image | select(contains($m)) | sub("@sha256:.*$"; "") | split(":") | last] | unique[]'
}

title "ceph-csi"
_m16_e33_csi="$(_m16_e33_tags ceph-csi cephcsi/cephcsi)" || _m16_e33_csi=""
check_cmd "une seule version de cephcsi dans l'espace ceph-csi ($(paste -sd ' ' - <<<"$_m16_e33_csi"))" \
  bash -c '[[ -n "$1" && $(wc -l <<<"$1") -eq 1 ]]' _ "$_m16_e33_csi"
check_cmd "cephcsi en 3.18.x, au moins 3.18.1" _m16_e33_au_moins "$_m16_e33_csi" 3.18.1 3.18.
_m16_e33_ds="$(_m16p_kj daemonsets -n ceph-csi)"
check_cmd "DaemonSets de ceph-csi entièrement mis à jour et prêts" \
  _m16p_jq "$_m16_e33_ds" '(.items | length) >= 2 and all(.items[]; .status.updatedNumberScheduled == .status.desiredNumberScheduled and .status.numberReady == .status.desiredNumberScheduled)'
check_cmd "Deployments de ceph-csi entièrement mis à jour et prêts" \
  _m16p_jq "$(_m16p_kj deployments -n ceph-csi)" '(.items | length) >= 2 and all(.items[]; (.status.updatedReplicas // 0) == .spec.replicas and (.status.readyReplicas // 0) == .spec.replicas)'

title "CloudNativePG et plugin Barman Cloud"
_m16_e33_op="$(_m16_e33_tags cnpg-system cloudnative-pg/cloudnative-pg)" || _m16_e33_op=""
_m16_e33_pl="$(_m16_e33_tags cnpg-system plugin-barman-cloud)" || _m16_e33_pl=""
check_cmd "opérateur en 1.30.x, au moins 1.30.1 ($(paste -sd ' ' - <<<"$_m16_e33_op"))" \
  _m16_e33_au_moins "$(head -n 1 <<<"$_m16_e33_op")" 1.30.1 1.30.
check_cmd "plugin Barman Cloud en 0.15.x, au moins 0.15.1 ($(paste -sd ' ' - <<<"$_m16_e33_pl"))" \
  _m16_e33_au_moins "$(head -n 1 <<<"$_m16_e33_pl")" 0.15.1 0.15.
_m16_e33_cl="$(_m16p_kj clusters.postgresql.cnpg.io -A)"
check_cmd "tous les Cluster du lab sont sains" \
  _m16p_jq "$_m16_e33_cl" '(.items | length) > 0 and all(.items[]; .status.phase == "Cluster in healthy state")'
check_cmd "archivage continu actif pour chaque Cluster qui archive" \
  _m16p_jq "$_m16_e33_cl" 'all(.items[] | select(any(.spec.plugins[]?; .isWALArchiver == true)); any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True"))'
check_cmd "aucun Cluster n'utilise l'archivage intégré barmanObjectStore (supprimé en 1.31)" \
  _m16p_jq "$_m16_e33_cl" 'all(.items[]; .spec.backup.barmanObjectStore == null)'

title "Après la mise à jour"
check_cmd "la sonde ms-verif-k8s-stockage est verte" timeout 240 /usr/local/bin/ms-verif-k8s-stockage --quiet
check_cmd "aucun témoin ne subsiste dans wb-essais" \
  _m16p_jq "$(_m16p_kj deployments,pvc -n wb-essais)" 'all(.items[]?; (.metadata.name | startswith("temoin-")) | not)'

title "Code et documentation"
check_cmd "RB-164 sur main de plateforme/medisphere" _m16p_doc_prefixe docs/kubernetes/stockage RB-164 'témoin|temoin' 'rollback|retour arrière'
check_cmd "compte rendu tests/mise-a-jour-stockage.md" \
  _m16p_doc_main docs/kubernetes/stockage/tests/mise-a-jour-stockage.md 'ceph-csi' 'CloudNativePG|cnpg' 'témoin|temoin'
check_cmd "plateforme/k8s : dernier pipeline de main réussi" _m16p_pipeline_ok plateforme/k8s
