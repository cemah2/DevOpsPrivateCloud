# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E23.sh — M18-E23 « Sous le capot : k3s, un binaire, une base, un superviseur »
# Lecture seule : synthèse sur main, absence de copie de la base sur k3s01 (find en lecture, dossiers
# temporaires et personnels), ConfigMap et AddOn d'essai retirés (kubeconfig k3s01).

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E23 — Sous le capot de k3s"
require_cmd kubectl jq ssh

_e23_doc=docs/kubernetes/distributions/analyses/k3s-sous-le-capot.md
check_cmd "synthèse publiée : processus unique, binaires extraits, kine/SQLite, superviseur, containerd, AddOn" \
  _m18p_fichier_contient plateforme/medisphere "$_e23_doc" \
  'kine' 'sqlite' 'superviseur|supervisor' 'cacerts' 'containerd' 'addon' 'rancher/k3s/data' '6443'
_e23_lignes() {
  local c
  c="$(_m18p_fichier_main plateforme/medisphere "$_e23_doc")" || return 1
  (( $(grep -c '^|' <<<"$c") >= 10 ))
}
check_cmd "tableau de correspondance kubeadm → k3s d'au moins huit lignes" _e23_lignes

check_ssh_output "k3s01 : aucune copie de la base hors de /var/lib/rancher/k3s/server/db" k3s01 '^0$' \
  'sudo -n find /tmp /var/tmp /root /home -xdev \( -name "*.db" -o -name "*.db-wal" -o -name "*.sqlite*" \) 2>/dev/null | wc -l'
_e23_cm_absente() {
  _m18p_joignable "$_M18P_KC_GESTION" || return 1
  ! _m18p_k "$_M18P_KC_GESTION" -n wb-essais get configmap addon-temoin -o name
}
check_cmd "k3s01 : plus de ConfigMap wb-essais/addon-temoin" _e23_cm_absente
_e23_addons="$(_m18p_gjson get addons.k3s.cattle.io -A)"
check_cmd "k3s01 : plus d'AddOn d'essai (addon-temoin)" _m18p_jq "$_e23_addons" \
  '[.items[]? | select((.metadata.name | test("addon-temoin")) or ((.spec.source // "") | test("addon-temoin")))] | length == 0'
