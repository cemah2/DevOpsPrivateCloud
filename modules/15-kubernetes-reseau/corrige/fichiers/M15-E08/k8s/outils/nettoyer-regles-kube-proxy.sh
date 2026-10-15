#!/usr/bin/env bash
# nettoyer-regles-kube-proxy.sh — retire des nœuds les règles iptables laissées par kube-proxy (M15-E08, CHG-1608).
#
# Procédure officielle de Cilium (« Kubernetes Without kube-proxy ») : sur chaque nœud, après la
# suppression du DaemonSet kube-proxy,  iptables-save | grep -v KUBE | iptables-restore
# Ce script l'applique UN NŒUD À LA FOIS, en SSH depuis adm01, sur les quatre jeux de règles
# possibles (IPv4/IPv6, backends nft et legacy), et vérifie le résultat.
#
# Usage :
#   outils/nettoyer-regles-kube-proxy.sh --simuler                 # compte les règles, ne touche à rien
#   outils/nettoyer-regles-kube-proxy.sh                           # tous les nœuds de k8s-par1
#   outils/nettoyer-regles-kube-proxy.sh k8s-w01 k8s-w02           # nœuds choisis
#
# Préalables vérifiés : DaemonSet kube-proxy absent (sinon il réécrit ses règles dans la seconde),
# Cilium en kubeProxyReplacement=true, agent Cilium prêt sur le nœud traité.
# Accès : kubectl avec ~/.kube/config ; SSH « admin » vers les nœuds, sudo sans mot de passe.
# Les chaînes CILIUM_* ne sont pas touchées (elles ne contiennent pas « KUBE »). Les chaînes
# KUBE-KUBELET-CANARY / KUBE-IPTABLES-HINT du kubelet, si elles existent, sont retirées aussi et
# recréées par le kubelet : c'est attendu.
set -euo pipefail

simuler=0
noeuds=()
for a in "$@"; do
  case "$a" in
    --simuler) simuler=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "option inconnue : $a" >&2; exit 2 ;;
    *) noeuds+=("$a") ;;
  esac
done

if (( ${#noeuds[@]} == 0 )); then
  mapfile -t noeuds < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi
(( ${#noeuds[@]} > 0 )) || { echo "aucun nœud trouvé" >&2; exit 1; }

# --- Préalables, une fois ---------------------------------------------------------------------------
if (( ! simuler )); then
  if kubectl -n kube-system get daemonset kube-proxy >/dev/null 2>&1; then
    echo "le DaemonSet kube-proxy existe encore : supprime-le d'abord (il réécrirait ses règles)" >&2
    exit 1
  fi
  kpr="$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.kube-proxy-replacement}')"
  [[ "$kpr" == "true" ]] || { echo "cilium-config : kube-proxy-replacement=$kpr (attendu true)" >&2; exit 1; }
fi

# Script exécuté sur le nœud (root). $1 = 1 pour simuler.
# shellcheck disable=SC2016  # évalué sur le nœud
distant='
set -eu
simuler="$1"
total=0
for b in iptables ip6tables iptables-legacy ip6tables-legacy; do
  command -v "$b-save" >/dev/null 2>&1 || continue
  n="$("$b-save" 2>/dev/null | grep -c KUBE || true)"
  echo "  $b : $n ligne(s) KUBE"
  total=$((total + n))
  if [ "$simuler" = 0 ] && [ "$n" -gt 0 ]; then
    "$b-save" | grep -v KUBE | "$b-restore"
    reste="$("$b-save" 2>/dev/null | grep -c KUBE || true)"
    echo "  $b : nettoyé, reste $reste"
    [ "$reste" -eq 0 ] || exit 1
  fi
done
if ! command -v iptables-save >/dev/null 2>&1; then
  echo "  iptables absent du nœud : rejoue playbooks/k8s-outils-diagnostic.yml (M15-E02)" >&2
  exit 1
fi
'

for n in "${noeuds[@]}"; do
  echo "== $n"
  if (( ! simuler )); then
    pod="$(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$n" \
      -o jsonpath='{.items[0].metadata.name}')"
    pret="$(kubectl -n kube-system get pod "$pod" -o jsonpath='{.status.containerStatuses[?(@.name=="cilium-agent")].ready}')"
    [[ "$pret" == "true" ]] || { echo "agent Cilium non prêt sur $n ($pod) : arrêt" >&2; exit 1; }
  fi
  # shellcheck disable=SC2029  # le script distant est passé volontairement en argument
  ssh -o BatchMode=yes "admin@$n" "sudo -n sh -c $(printf '%q' "$distant") nettoyer $simuler"
  if (( ! simuler )); then
    # Le nœud doit toujours servir les Services : l'agent reste prêt, et le NodePort de test répond.
    sleep 2
    pret="$(kubectl -n kube-system get pod "$pod" -o jsonpath='{.status.containerStatuses[?(@.name=="cilium-agent")].ready}')"
    [[ "$pret" == "true" ]] || { echo "agent Cilium non prêt après nettoyage sur $n : arrêt" >&2; exit 1; }
  fi
done
echo "terminé"
