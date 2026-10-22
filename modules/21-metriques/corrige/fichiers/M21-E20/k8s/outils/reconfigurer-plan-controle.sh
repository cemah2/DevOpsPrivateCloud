#!/usr/bin/env bash
# =============================================================================
# outils/reconfigurer-plan-controle.sh — plateforme/k8s (M21-E20, PLAT-2220) : appliquer la
# ClusterConfiguration de cluster/kubeadm-config.yaml à UN composant statique d'UN nœud de
# contrôle, depuis adm01, avec retour arrière automatique. Généralise reconfigurer-apiserver.sh
# (M14-E27) ; méthode de la page « Reconfiguring a kubeadm cluster » :
#   controller-manager : kubeadm init phase control-plane controller-manager --config <fichier>
#   scheduler          : kubeadm init phase control-plane scheduler --config <fichier>
#   etcd               : kubeadm init phase etcd local --config <fichier>
#
# Usage : outils/reconfigurer-plan-controle.sh COMPOSANT NŒUD
#         outils/reconfigurer-plan-controle.sh --televerser NŒUD
#           (kubeadm init phase upload-config kubeadm : UNE fois, quand les trois nœuds sont passés)
# Ordre conseillé : controller-manager et scheduler sur les trois nœuds, PUIS etcd nœud par nœud.
# Prérequis : yq (mikefarah) sur adm01, SSH admin + sudo vers le nœud, dépôt à jour sur main,
# instantané etcd vérifié AVANT de toucher à etcd (RB-141).
# =============================================================================
set -Eeuo pipefail
umask 077

declare -A ip=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53)
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

televerser=0
if [[ "${1:-}" == --televerser ]]; then televerser=1; composant=""; noeud="${2:-}"; else composant="${1:-}"; noeud="${2:-}"; fi
[[ -n "$noeud" && -n "${ip[$noeud]:-}" ]] || usage
if (( ! televerser )); then
  case "$composant" in controller-manager|scheduler|etcd) ;; *) usage ;; esac
fi
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_cfg="$racine/cluster/kubeadm-config.yaml"
command -v yq >/dev/null || { echo "yq (mikefarah) manquant" >&2; exit 1; }

cc="$(yq eval-all 'select(.kind == "ClusterConfiguration")' "$source_cfg")"
[[ -n "$cc" ]] || { echo "pas de ClusterConfiguration dans $source_cfg" >&2; exit 1; }
# Fichier du nœud : ClusterConfiguration du dépôt + InitConfiguration PROPRE AU NŒUD (adresse
# annoncée) ; réutiliser celle d'un autre nœud ferait annoncer la mauvaise adresse.
cfg="$(printf '%s\n---\napiVersion: kubeadm.k8s.io/v1beta4\nkind: InitConfiguration\nlocalAPIEndpoint:\n  advertiseAddress: %s\n  bindPort: 6443\nnodeRegistration:\n  name: %s\n' \
  "$cc" "${ip[$noeud]}" "$noeud")"

echo "== $noeud : dépôt du fichier de configuration du nœud"
ssh "$noeud" 'sudo -n install -d -m 700 /root/kubeadm-reconf && sudo -n tee /root/kubeadm-reconf/kubeadm.yaml >/dev/null' <<<"$cfg"
ssh "$noeud" 'sudo -n kubeadm config validate --config /root/kubeadm-reconf/kubeadm.yaml'

if (( televerser )); then
  echo "== mise à jour du ConfigMap kube-system/kubeadm-config depuis $noeud"
  ssh "$noeud" 'sudo -n kubeadm init phase upload-config kubeadm --config /root/kubeadm-reconf/kubeadm.yaml'
  exit 0
fi

case "$composant" in
  controller-manager)
    manifeste=kube-controller-manager.yaml; conteneur=kube-controller-manager
    phase="control-plane controller-manager"; sante="curl -sk --max-time 3 https://127.0.0.1:10257/healthz" ;;
  scheduler)
    manifeste=kube-scheduler.yaml; conteneur=kube-scheduler
    phase="control-plane scheduler"; sante="curl -sk --max-time 3 https://127.0.0.1:10259/healthz" ;;
  etcd)
    manifeste=etcd.yaml; conteneur=etcd
    phase="etcd local"; sante="curl -s --max-time 3 http://127.0.0.1:2381/health" ;;
esac

if [[ "$composant" == etcd ]]; then
  echo "== quorum etcd AVANT (depuis le conteneur etcd de $noeud)"
  # shellcheck disable=SC2016  # évalué sur le nœud
  ssh "$noeud" 'sudo -n bash -c '\''id=$(crictl ps --name "^etcd$" -q | head -1); crictl exec "$id" etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health --cluster'\'''
fi

echo "== $noeud : régénération de $manifeste (copie de retour arrière HORS de /etc/kubernetes/manifests)"
# Variables développées ICI, volontairement (valeurs fixes du « case » ci-dessus, sans espace
# piège ni donnée externe), puis transmises au script distant par env.
# shellcheck disable=SC2029
ssh "$noeud" "sudo -n env MANIFESTE='$manifeste' CONTENEUR='$conteneur' PHASE='$phase' SANTE='$sante' bash -s" <<'DISTANT'
set -Eeuo pipefail
m="/etc/kubernetes/manifests/$MANIFESTE"
avant="/root/kubeadm-reconf/$MANIFESTE.avant-$(date +%Y%m%dT%H%M%S)"
cp -a "$m" "$avant"
ancien_id="$(crictl ps --name "^${CONTENEUR}\$" -q 2>/dev/null | head -1)"
# shellcheck disable=SC2086  # PHASE contient deux mots (ex. « control-plane scheduler »)
kubeadm init phase $PHASE --config /root/kubeadm-reconf/kubeadm.yaml
if cmp -s "$avant" "$m"; then
  echo "manifeste inchangé : le kubelet ne relancera rien sur $(hostname -s)"
  exit 0
fi
diff -u "$avant" "$m" || true
# L'ANCIEN conteneur répond encore quelques secondes : attendre un NOUVEAU conteneur avant de
# croire le point de santé, sinon on validerait l'ancien processus.
echo "attente du nouveau conteneur $CONTENEUR, puis de son point de santé…"
for _ in $(seq 1 60); do
  sleep 5
  id="$(crictl ps --name "^${CONTENEUR}\$" -q 2>/dev/null | head -1)"
  [[ -n "$id" && "$id" != "$ancien_id" ]] || continue
  if $SANTE | grep -Eq '^ok$|"health":"true"'; then
    echo "$CONTENEUR de $(hostname -s) sain (nouveau conteneur ${id:0:13})"
    exit 0
  fi
done
echo "ÉCHEC : $CONTENEUR ne redevient pas sain ; retour arrière vers $avant" >&2
cp -a "$avant" "$m"
exit 1
DISTANT

if [[ "$composant" == etcd ]]; then
  echo "== quorum etcd APRÈS"
  # shellcheck disable=SC2016  # évalué sur le nœud
  ssh "$noeud" 'sudo -n bash -c '\''id=$(crictl ps --name "^etcd$" -q | head -1); crictl exec "$id" etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health --cluster'\'''
fi
echo "== $noeud : $composant terminé. Vérifie, puis passe au nœud suivant."
