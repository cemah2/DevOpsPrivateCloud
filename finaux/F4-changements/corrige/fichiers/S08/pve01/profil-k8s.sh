#!/usr/bin/env bash
# pve01 — profil-k8s.sh (F4-S08, CHG-3408) : arrêt et démarrage ordonnés de k8s-par1 pour libérer la
# mémoire de la montée d'OpenStack (PLAN §4.14 : socle + ceph-par1 + openstack ≈ 101 Go).
# Ordre de lab/topologie.md : arrêt des travailleurs 2146, 2145, 2144 puis des nœuds de contrôle 2143,
# 2142, 2141 ; démarrage dans l'ordre inverse (ceph-par1 en HEALTH_OK d'abord).
#   root@pve01:~# ./profil-k8s.sh arreter
#   root@pve01:~# ./profil-k8s.sh demarrer
# ⚠️ Arrêter k8s-par1 arrête MédiAgenda, MédiNotif, le portail… dans le lab : c'est une contrainte de
# MÉMOIRE du lab, annoncée dans CHG-3408 (la sonde ne mesure alors que l'IP flottante d'OpenStack).
set -euo pipefail

TRAVAILLEURS=(2146 2145 2144)
CONTROLE=(2143 2142 2141)

attendre_etat() {
  local v="$1" etat="$2" i
  for ((i = 0; i < 60; i++)); do
    qm status "$v" | grep -q "status: $etat" && return 0
    sleep 5
  done
  echo "VM $v : état « $etat » non atteint" >&2
  return 1
}

case "${1:-}" in
  arreter)
    for v in "${TRAVAILLEURS[@]}" "${CONTROLE[@]}"; do
      qm config "$v" | grep -q '^name: k8s-' || { echo "VM $v : ce n'est pas un nœud k8s-par1, arrêt" >&2; exit 1; }
      echo "arrêt de $v ($(qm config "$v" | sed -n 's/^name: //p'))"
      qm shutdown "$v" --timeout 300 || { echo "VM $v : arrêt propre impossible en 5 min — regarde avant de forcer" >&2; exit 1; }
      attendre_etat "$v" stopped
    done
    ;;
  demarrer)
    for v in 2081 2082 2083; do qm status "$v" | grep -q 'status: running' || { echo "ceph-par1 n'est pas démarré ($v)" >&2; exit 1; }; done
    for v in "${CONTROLE[@]}"; do qm start "$v"; attendre_etat "$v" running; sleep 30; done
    for v in "${TRAVAILLEURS[@]}"; do qm start "$v"; attendre_etat "$v" running; done
    echo "démarré : attends tous les nœuds Ready (kubectl get nodes) puis lab/bin/check F4 2"
    ;;
  *) echo "Usage : $0 arreter|demarrer" >&2; exit 2 ;;
esac
