# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M18-E14 « Sauvegarder et restaurer selon la distribution »
# Lecture seule : compartiment etcd-m18 (identité etcd-m18 : liste et lecture des 21 premiers octets),
# talosconfig de sauvegarde (certificat), témoins et nœuds des clusters ALLUMÉS (les autres sont signalés
# ignorés), fragments de configuration S3 des serveurs (stat par SSH), documentation sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E14 — Sauvegarder et restaurer selon la distribution"
require_cmd kubectl jq aws ssh yq openssl

title "Stockage objet (s3-01, compartiment etcd-m18)"
check_cmd "identité etcd-m18 sur adm01 en 600 ($_M18P_S3_ENV)" _m18p_local600 "$_M18P_S3_ENV"
check_output "le compartiment etcd-m18 est versionné" '"Status": *"Enabled"' \
  _m18p_s3 s3api get-bucket-versioning --bucket etcd-m18
check_cmd "k3s-ha/ : instantané de moins de 7 h (planification du banc k3s etcd)" _m18p_s3_recent k3s-ha/ 25200
check_cmd "rke2/ : instantané de moins de 7 h (planification des serveurs RKE2)" _m18p_s3_recent rke2/ 25200
check_cmd "talos/ : instantané de moins de 7 jours" _m18p_s3_recent talos/ 604800
_e14_cle="$(_m18p_s3_dernier talos/ | cut -f1)" || _e14_cle=""
if [[ -n "$_e14_cle" ]]; then
  check_cmd "talos/ : le dernier instantané est chiffré par age" _m18p_s3_chiffre "$_e14_cle"
else
  check_cmd "talos/ : le dernier instantané est chiffré par age (aucun objet)" false
fi
_e14_g="$(_m18p_s3 s3api list-objects-v2 --bucket etcd-m18 --prefix gestion/ 2>/dev/null)" || _e14_g=null
_e14_k3s01="$(jq -r '[.Contents[]? | select(.Key | test("k3s01"))] | sort_by(.LastModified) | last | .Key // empty' <<<"$_e14_g" 2>/dev/null)" || _e14_k3s01=""
_e14_capi="$(jq -r '[.Contents[]? | select(.Key | test("capi"))] | sort_by(.LastModified) | last | .Key // empty' <<<"$_e14_g" 2>/dev/null)" || _e14_capi=""
check_cmd "gestion/ : archive de k3s01 chiffrée par age" bash -c '[[ -n "$1" ]]' _ "$_e14_k3s01"
if [[ -n "$_e14_k3s01" ]]; then check_cmd "gestion/ : en-tête age sur l'archive de k3s01" _m18p_s3_chiffre "$_e14_k3s01"; fi
check_cmd "gestion/ : export Cluster API (clusterctl move --to-directory) chiffré par age" bash -c '[[ -n "$1" ]]' _ "$_e14_capi"
if [[ -n "$_e14_capi" ]]; then check_cmd "gestion/ : en-tête age sur l'export Cluster API" _m18p_s3_chiffre "$_e14_capi"; fi

title "Talos : identité de sauvegarde"
_e14_tcs="$_M18P_DIR/talosconfig-sauvegarde"
check_cmd "talosconfig-sauvegarde en 600" _m18p_local600 "$_e14_tcs"
_e14_roles="$(_m18p_talos_roles "$_e14_tcs" | sort -u | tr '\n' ' ')" || _e14_roles=""
check_output "talosconfig-sauvegarde : le seul rôle est os:etcd:backup (lu : ${_e14_roles:-aucun})" '^os:etcd:backup $' \
  echo "$_e14_roles"

title "Configuration des instantanés sur les serveurs"
_e14_frag() { _m18p_sudo "$1" "stat -c %a $2" | grep -qx 600 && _m18p_sudo "$1" "grep -Eq '^etcd-s3: *true' $2"; }
check_cmd "k3s-ha01 : fragment etcd-s3 en 600 (config.yaml.d)" _e14_frag k3s-ha01 /etc/rancher/k3s/config.yaml.d/50-etcd-s3.yaml
for _e14_n in "${_M18P_RKE2[@]}"; do
  check_cmd "$_e14_n : fragment etcd-s3 en 600 (config.yaml.d)" _e14_frag "$_e14_n" /etc/rancher/rke2/config.yaml.d/50-etcd-s3.yaml
done

title "Restaurations (clusters allumés)"
_e14_restaure() {
  local nom="$1" kc="$2"
  if ! _m18p_joignable "$kc"; then
    skip "$nom : témoin et nœuds" "cluster éteint ou injoignable (allume-le pour le contrôler)"
    return 0
  fi
  check_output "$nom : témoin wb-essais/temoin-restauration = avant-instantane" '^avant-instantane$' _m18p_temoin "$kc"
  check_cmd "$nom : tous les nœuds Ready" _m18p_noeuds_prets "$kc" 2
}
_e14_restaure "k3s etcd (k3s-ha)" "$_M18P_KC_K3SHA"
if _m18p_joignable "$_M18P_KC_K3SHA"; then
  _e14_esf="$(_m18p_json "$_M18P_KC_K3SHA" get etcdsnapshotfiles.k3s.cattle.io)"
  check_cmd "k3s-ha : au moins un ETCDSnapshotFile stocké dans S3" _m18p_jq "$_e14_esf" '[.items[]? | select(.spec.s3 != null)] | length >= 1'
fi
_e14_restaure "RKE2" "$_M18P_KC_RKE2"
_e14_restaure "Talos" "$_M18P_KC_TALOS"

title "Code et documentation"
check_cmd "plateforme/distributions (main) : talos/outils/etcd-instantane.sh (snapshot, contrôle, age)" \
  _m18p_fichier_contient plateforme/distributions talos/outils/etcd-instantane.sh 'etcd snapshot' 'snapshot status' 'age'
check_cmd "RB-181 publié (k3s, RKE2, Talos, cluster de gestion, renvoi vers RB-141)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-181 'k3s' 'rke2' 'talos' 'clusterctl move|gestion' 'RB-141'
check_cmd "compte rendu tests/restaurations.md (RTO, RPO, comparaison avec kubeadm)" \
  _m18p_fichier_contient plateforme/medisphere docs/kubernetes/distributions/tests/restaurations.md 'RTO' 'RPO' 'kubeadm'
