#!/usr/bin/env bash
# plateforme/k8s — outils/temoins-stockage.sh (M16-E33)
# Pendant une mise à jour du stockage :
#   provisionnement : crée puis supprime un PVC ceph-rbd par minute (wb-essais) et journalise la
#                     durée jusqu'à Bound (classe en WaitForFirstConsumer : un pod éphémère le monte) ;
#   trous           : après coup, liste les trous de plus de 2 s dans les horodatages des témoins.
# Usage : temoins-stockage.sh provisionnement | trous
set -euo pipefail
ns=wb-essais

case "${1:-}" in
  provisionnement)
    trap 'echo; echo arrêt; exit 0' INT TERM
    while :; do
      n="e33-prov-$(date +%H%M%S)"
      debut=$(date +%s)
      kubectl apply -f - >/dev/null <<FIN
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $n, namespace: $ns}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources: {requests: {storage: 100Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: $n, namespace: $ns}
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: c
    image: registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim
    command: ["true"]
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
    volumeMounts: [{name: v, mountPath: /v}]
  volumes: [{name: v, persistentVolumeClaim: {claimName: $n}}]
FIN
      if kubectl wait --for=jsonpath='{.status.phase}'=Bound "pvc/$n" -n "$ns" --timeout=120s >/dev/null 2>&1; then
        echo "$(date +%T) $n lié en $(( $(date +%s) - debut )) s"
      else
        echo "$(date +%T) $n NON lié après 120 s"
      fi
      kubectl delete pod,pvc "$n" -n "$ns" --wait=false >/dev/null 2>&1 || true
      sleep 60
    done
    ;;
  trous)
    for t in e33-temoin-rbd e33-temoin-cephfs; do
      echo "== $t"
      kubectl exec -n "$ns" "deploy/$t" -- cat /donnees/horodatages.log \
        | awk 'NR > 1 && $1 - p > 2 { print p, $1 - p } { p = $1 }' \
        | while read -r t0 d; do echo "trou de $d s après $(date -d "@$t0" +%T)"; done
    done
    ;;
  *) echo "usage : $0 provisionnement | trous" >&2; exit 2 ;;
esac
