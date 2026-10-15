# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E03.sh — M18-E03 : k3s, un cluster léger pour l'agence
# À lancer depuis adm01. Lecture seule : qm config, SSH vers k3s01 (versions, fichiers, sha256sum),
# kubectl get avec k3s01.kubeconfig, API Harbor et GitLab en GET.

# shellcheck source=_m18-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-decouverte.sh"

title "M18-E03 — k3s : un cluster léger pour l'agence"
require_cmd jq kubectl

_m18d_vm "k3s01" 2181 k3s01 2 4096 "bc:24:11:99:18:81" env-m18 role-k3s

# --- 1. Le nœud -------------------------------------------------------------------------------
check_output "k3s01 : k3s v1.36.5+k3s1" 'k3s version v1\.36\.5\+k3s1 ' remote "$_M18D_K3S" 'k3s --version'
check_ssh "k3s01 : service k3s actif" "$_M18D_K3S" 'systemctl is-active --quiet k3s'
check_ssh "k3s01 : base SQLite (kine), pas d'etcd intégré" "$_M18D_K3S" \
  'sudo -n test -f /var/lib/rancher/k3s/server/db/state.db && ! sudo -n test -d /var/lib/rancher/k3s/server/db/etcd'
check_output "k3s01 : script d'installation conservé, empreinte figée" '^46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad ' \
  remote "$_M18D_K3S" 'sudo -n sha256sum /usr/local/lib/k3s/install-v1.36.5+k3s1.sh'
check_ssh "k3s01 : jeton dans un fichier 600, pas dans l'environnement du service" "$_M18D_K3S" \
  '[ "$(sudo -n stat -c %a /etc/rancher/k3s/jeton)" = 600 ] && ! sudo -n grep -qs K3S_TOKEN /etc/systemd/system/k3s.service.env'
check_output "k3s01 : containerd renvoie docker.io vers le cache Harbor" 'registry\.par1\.medisphere\.internal/v2/dockerhub' \
  remote "$_M18D_K3S" 'sudo -n cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml'

# --- 2. Le cluster ---------------------------------------------------------------------------
_m18d_e03_kc="$_M18D_DIR/k3s01.kubeconfig"
check_cmd "k3s01.kubeconfig en 600" _m18d_600 "$_m18d_e03_kc"
check_output "k3s01.kubeconfig : serveur https://k3s01.par1.medisphere.internal:6443" '^https://k3s01\.par1\.medisphere\.internal:6443$' \
  _m18d_serveur k3s01
check_cmd "Le nœud k3s01 est Ready en v1.36.5+k3s1 (TLS vérifié par le nom)" _m18d_noeuds_prets \
  "$(_m18d_kj k3s01 get nodes -o json)" 1 v1.36.5+k3s1
_m18d_e03_ks="$(_m18d_kj k3s01 -n kube-system get deployments,daemonsets -o json)"
check_cmd "Traefik et ServiceLB absents" _m18d_json "$_m18d_e03_ks" \
  '(.items | length > 0) and ([.items[].metadata.name | select(test("^traefik$|^svclb-"))] | length == 0)'
check_cmd "local-path-provisioner et metrics-server présents" _m18d_json "$_m18d_e03_ks" \
  '([.items[].metadata.name] | index("local-path-provisioner")) and ([.items[].metadata.name] | index("metrics-server"))'
check_cmd "agence/whoami : deux réplicas prêts, image docker.io/traefik/whoami:v1.11.0" _m18d_json \
  "$(_m18d_kj k3s01 -n agence get deployment whoami -o json)" \
  '.status.readyReplicas == 2 and .spec.template.spec.containers[0].image == "docker.io/traefik/whoami:v1.11.0"'
check_cmd "Harbor : l'image whoami est passée par le cache (dépôt dockerhub/traefik/whoami)" _m18d_json \
  "$(harbor_api 'projects/dockerhub/repositories?q=name%3D~whoami&page_size=20' 2>/dev/null || true)" \
  'any(.[]; .name == "dockerhub/traefik/whoami")'

# --- 3. Le code et la documentation ---------------------------------------------------------
_m18d_fichiers_main plateforme/ansible roles/k3s/tasks/main.yml roles/k3s/templates/config.yaml.j2
check_output "plateforme/ansible (main) : host_vars/k3s01/k3s.yml (tls-san, traefik et servicelb désactivés)" 'servicelb' \
  _m18d_contenu_main plateforme/ansible inventories/lab/host_vars/k3s01/k3s.yml
_m18d_fichiers_main plateforme/distributions k3s/README.md k3s/agence/whoami.yaml
_m18d_fichiers_main plateforme/medisphere docs/kubernetes/distributions/k3s.md
