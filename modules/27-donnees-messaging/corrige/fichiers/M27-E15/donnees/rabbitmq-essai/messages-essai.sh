#!/usr/bin/env bash
# rabbitmq-essai/messages-essai.sh — prépare la répétition de montée (M27-E15, étape 6) : vhost « essai »,
# une file quorum et une file classique remplies de 1 000 messages persistants chacune, puis compte.
# Usage : messages-essai.sh preparer|compter   (depuis adm01, contexte k8s-par1, espace wb-essais)
# Les identifiants sont ceux, JETABLES, de la grappe d'essai (Secret de l'opérateur), lus par le pod dans
# son environnement : jamais ce modèle avec la grappe de production.
set -euo pipefail
ns=wb-essais
pod=rabbitmq-essai-server-0
image=registry.par1.medisphere.internal/dockerhub/pivotalrabbitmq/perf-test:2.25.0
ctl() { kubectl -n "$ns" exec "$pod" -c rabbitmq -- "$@"; }

remplir() {   # remplir NOM OPTION_DE_TYPE
  kubectl -n "$ns" delete job "remplir-$1" --ignore-not-found >/dev/null
  kubectl apply -f - <<JOB
apiVersion: batch/v1
kind: Job
metadata: {name: remplir-$1, namespace: $ns}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 2000, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: perf-test
          image: $image
          command: ["/bin/sh", "-c"]
          args:
            - exec java -jar /perf_test/perf-test.jar --uri "amqp://\${U}:\${P}@rabbitmq-essai.$ns.svc:5672/essai"
              -x 1 -y 0 -C 1000 -c 100 -s 1024 -f persistent -u essai-$1 --auto-delete false $2
          env:
            - {name: U, valueFrom: {secretKeyRef: {name: rabbitmq-essai-default-user, key: username}}}
            - {name: P, valueFrom: {secretKeyRef: {name: rabbitmq-essai-default-user, key: password}}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
JOB
  kubectl -n "$ns" wait --for=condition=complete --timeout=300s "job/remplir-$1"
}

case "${1:-}" in
  preparer)
    utilisateur="$(kubectl -n "$ns" get secret rabbitmq-essai-default-user -o jsonpath='{.data.username}' | base64 -d)"
    ctl rabbitmqctl add_vhost essai
    ctl rabbitmqctl set_permissions -p essai "$utilisateur" '.*' '.*' '.*'
    remplir quorum --quorum-queue
    remplir classique ""
    ;;
  compter)
    ctl rabbitmqctl list_queues -p essai name type messages
    ;;
  *) echo "usage : $0 preparer|compter" >&2; exit 2 ;;
esac
