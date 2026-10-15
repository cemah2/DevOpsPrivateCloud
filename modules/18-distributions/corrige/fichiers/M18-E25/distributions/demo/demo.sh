#!/usr/bin/env bash
# demo/demo.sh — démonstration reconstructible de l'option retenue (M18-E25). Lancé depuis adm01 par
# « task demo:construire » et « task demo:detruire ».
#   construire : VMs (OpenTofu, envs/m18), k3s trois serveurs (rôle k3s, etcd intégré, instantanés S3),
#                kubeconfig en 600, charge témoin, instantané à la demande ; affiche la durée.
#   detruire   : VMs détruites (liste vide, la charge témoin part avec elles), kubeconfig supprimé.
# Les variables de l'inventaire des trois nœuds (k3s_role server, k3s_cluster_init sur le premier,
# k3s_url des deux autres, dossier S3 « demo ») sont dans plateforme/ansible host_vars/k3s-ha0N/ : elles
# remplacent la paire serveur + agent des paliers 3 et 4 (voir host_vars/k3s-ha-demo.yml.extrait).
set -euo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null  # demo.env, à côté du script
. "$ici/demo.env"
src="${WB_SRC:-$HOME/src}"
tfvars="$src/infra/envs/m18/demo.auto.tfvars"

journal() { printf '%s %s\n' "$(date +%T)" "$*"; }

construire() {
  local debut liste n premier noeuds
  debut=$(date +%s)
  read -r -a noeuds <<<"$DEMO_NOEUDS"
  liste="$(printf '"%s", ' "${noeuds[@]}")"
  printf 'k3s_ha_noeuds = [%s]\n' "${liste%, }" >"$tfvars"
  journal "VMs : $DEMO_NOEUDS"
  tofu -chdir="$src/infra/envs/m18" apply -auto-approve
  journal "configuration : rôle k3s ($DEMO_VERSION)"
  ( cd "$src/ansible" && uv run ansible-playbook playbooks/m18.yml --limit "${DEMO_NOEUDS// /,}" -e "k3s_version=$DEMO_VERSION" )
  premier="${DEMO_NOEUDS%% *}"
  install -d -m 700 "$(dirname "$DEMO_KUBECONFIG")"
  ( umask 077
    ssh "$premier" 'sudo -n cat /etc/rancher/k3s/k3s.yaml' \
      | sed "s#https://127.0.0.1:6443#https://$premier.par1.medisphere.internal:6443#" >"$DEMO_KUBECONFIG" )
  export KUBECONFIG="$DEMO_KUBECONFIG"
  n="$(wc -w <<<"$DEMO_NOEUDS")"
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  [[ "$(kubectl get nodes --no-headers | wc -l)" -eq "$n" ]] || { echo "nombre de nœuds inattendu" >&2; exit 1; }
  kubectl apply -f "$ici/temoin.yaml"
  kubectl -n wb-essais rollout status deploy/temoin --timeout=180s
  ssh "$premier" "sudo -n k3s etcd-snapshot save --name demo"
  journal "démonstration prête en $(( $(date +%s) - debut )) s"
}

detruire() {
  printf 'k3s_ha_noeuds = []\n' >"$tfvars"
  tofu -chdir="$src/infra/envs/m18" apply -auto-approve
  rm -f "$DEMO_KUBECONFIG" "$tfvars"
  journal "démonstration détruite"
}

case "${1:-}" in
  construire) construire ;;
  detruire) detruire ;;
  *) echo "usage : $0 construire|detruire" >&2; exit 2 ;;
esac
