# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E07.sh — M18-E07 : k3s, haute disponibilité intégrée et mises à jour automatiques
# À lancer depuis adm01, AVANT de détruire le banc. Lecture seule : qm config, SSH (test -d),
# kubectl get avec k3s-ha.kubeconfig, GitLab en GET.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E07 — k3s : haute disponibilité intégrée et mises à jour automatiques"
require_cmd jq kubectl

for _m18d_e07_i in 1 2 3; do
  _m18d_e07_nom="k3s-ha0$_m18d_e07_i"
  _m18d_vm "$_m18d_e07_nom" "519$_m18d_e07_i" "$_m18d_e07_nom" 2 2048 "bc:24:11:99:18:9$_m18d_e07_i" env-m18 role-k3s-ha
  check_cmd "$_m18d_e07_nom : clone LIÉ de l'image dorée (disque adossé à un disque de base)" bash -c \
    'grep -Eq "^scsi0: [^,]*base-[0-9]+-disk-[0-9]+/" <<<"$1"' _ "$(_m18d_qm "519$_m18d_e07_i")"
  check_ssh "$_m18d_e07_nom : etcd intégré (dossier db/etcd)" "$_m18d_e07_nom" 'sudo -n test -d /var/lib/rancher/k3s/server/db/etcd'
done

_m18d_e07_noeuds="$(_m18d_kj k3s-ha get nodes -o json)"
check_cmd "Trois nœuds Ready en v1.36.5+k3s1 (montés par le contrôleur)" _m18d_noeuds_prets "$_m18d_e07_noeuds" 3 v1.36.5+k3s1
check_cmd "Les trois nœuds sont control-plane et etcd, et ont reçu le plan serveurs" _m18d_json "$_m18d_e07_noeuds" \
  'all(.items[]; .metadata.labels["node-role.kubernetes.io/etcd"] == "true" and .metadata.labels["node-role.kubernetes.io/control-plane"] == "true"
     and (.metadata.labels | has("plan.upgrade.cattle.io/serveurs")))'
check_cmd "system-upgrade-controller v0.20.2 disponible dans system-upgrade" _m18d_json \
  "$(_m18d_kj k3s-ha -n system-upgrade get deployment system-upgrade-controller -o json)" \
  '.spec.template.spec.containers[0].image | endswith(":v0.20.2")'
check_cmd "Plan serveurs : v1.36.5+k3s1, concurrence 1, cordon, fenêtre horaire" _m18d_json \
  "$(_m18d_kj k3s-ha -n system-upgrade get plan serveurs -o json)" \
  '.spec.version == "v1.36.5+k3s1" and .spec.concurrency == 1 and .spec.cordon == true and (.spec.window.days | length >= 1) and (.spec.channel // "" | length == 0)'

_m18d_fichiers_main plateforme/infra envs/m18/k3s-ha.tf
_m18d_fichiers_main plateforme/ansible inventories/lab/m18-k3s-ha.yml
check_output "plateforme/ansible (main) : k3s_gere_version: false sur le banc" '^k3s_gere_version: false' \
  _m18d_contenu_main plateforme/ansible inventories/lab/group_vars/k3s_ha/k3s.yml
_m18d_fichiers_main plateforme/distributions k3s/suc/kustomization.yaml k3s/suc/plan-serveurs.yaml
check_output "k3s.md (main) : section haute disponibilité et mises à jour automatiques" 'system-upgrade' \
  _m18d_contenu_main plateforme/medisphere docs/kubernetes/distributions/k3s.md
