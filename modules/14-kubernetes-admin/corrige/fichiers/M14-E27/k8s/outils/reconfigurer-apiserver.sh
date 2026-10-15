#!/usr/bin/env bash
# =============================================================================
# outils/reconfigurer-apiserver.sh — plateforme/k8s (M14-E27, E28) : appliquer la ClusterConfiguration
# de cluster/kubeadm-config.yaml au serveur d'API d'UN nœud de contrôle, depuis adm01, avec retour
# arrière automatique. Méthode de la page « Reconfiguring a kubeadm cluster » :
#   kubeadm init phase control-plane apiserver --config <fichier du nœud>
# Le fichier du nœud = la ClusterConfiguration du dépôt + une InitConfiguration PROPRE AU NŒUD
# (adresse annoncée) : réutiliser celle de k8s-cp01 sur k8s-cp02 ferait annoncer la mauvaise adresse.
#
# Usage : outils/reconfigurer-apiserver.sh NŒUD            (un nœud ; recommence pour les deux autres)
#         outils/reconfigurer-apiserver.sh --televerser NŒUD
#           met à jour le ConfigMap kube-system/kubeadm-config depuis ce nœud
#           (kubeadm init phase upload-config kubeadm) : à faire UNE fois, quand les trois nœuds sont
#           passés, sinon la prochaine montée de version (RB-142) régénère les manifestes SANS tes options.
# Prérequis : yq (mikefarah) sur adm01, SSH admin + sudo vers le nœud, dépôt à jour sur main.
# =============================================================================
set -Eeuo pipefail
umask 077

televerser=0
if [[ "${1:-}" == --televerser ]]; then televerser=1; shift; fi
noeud="${1:-}"
declare -A ip=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53)
[[ -n "$noeud" && -n "${ip[$noeud]:-}" ]] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_cfg="$racine/cluster/kubeadm-config.yaml"
command -v yq >/dev/null || { echo "yq (mikefarah) manquant" >&2; exit 1; }

cc="$(yq eval-all 'select(.kind == "ClusterConfiguration")' "$source_cfg")"
[[ -n "$cc" ]] || { echo "pas de ClusterConfiguration dans $source_cfg" >&2; exit 1; }
cfg="$(printf '%s\n---\napiVersion: kubeadm.k8s.io/v1beta4\nkind: InitConfiguration\nlocalAPIEndpoint:\n  advertiseAddress: %s\n  bindPort: 6443\nnodeRegistration:\n  name: %s\n' \
  "$cc" "${ip[$noeud]}" "$noeud")"

echo "== $noeud : dépôt du fichier de configuration du nœud"
ssh "$noeud" 'sudo -n install -d -m 700 /root/kubeadm-reconf && sudo -n tee /root/kubeadm-reconf/kubeadm.yaml >/dev/null' <<<"$cfg"
ssh "$noeud" 'sudo -n kubeadm config validate --config /root/kubeadm-reconf/kubeadm.yaml'

if (( televerser )); then
  echo "== mise à jour du ConfigMap kubeadm-config depuis $noeud"
  ssh "$noeud" 'sudo -n kubeadm init phase upload-config kubeadm --config /root/kubeadm-reconf/kubeadm.yaml'
  exit 0
fi

echo "== $noeud : régénération du manifeste du serveur d'API (copie de retour arrière HORS de /etc/kubernetes/manifests)"
# shellcheck disable=SC2016  # évalué sur le nœud
ssh "$noeud" 'sudo -n bash -s' <<'DISTANT'
set -Eeuo pipefail
m=/etc/kubernetes/manifests/kube-apiserver.yaml
avant=/root/kubeadm-reconf/kube-apiserver.yaml.avant-$(date +%Y%m%dT%H%M%S)
cp -a "$m" "$avant"
kubeadm init phase control-plane apiserver --config /root/kubeadm-reconf/kubeadm.yaml
diff -u "$avant" "$m" || true
echo "attente du serveur d'API local (readyz)…"
for _ in $(seq 1 60); do
  sleep 5
  if curl -sk --max-time 3 https://127.0.0.1:6443/readyz | grep -qx ok; then
    echo "serveur d'API de $(hostname -s) prêt"
    exit 0
  fi
done
echo "ÉCHEC : le serveur d'API ne revient pas ; retour arrière vers $avant" >&2
cp -a "$avant" "$m"
exit 1
DISTANT
echo "== $noeud : terminé. Vérifie, puis passe au nœud suivant."
