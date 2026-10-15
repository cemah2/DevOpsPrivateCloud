#!/usr/bin/env bash
# refus.sh — essais de l'étape 5 de M16-E20, en se faisant passer pour Julien (impersonation :
# il faut le droit « impersonate », que le groupe medisphere:plateforme-admins a). Chaque essai
# est en --dry-run=server : rien n'est créé, mais admission, quotas et LimitRange sont évalués.
set -uo pipefail
ns=mediagenda-dev
qui=(--as=julien.petit --as-group=medisphere:mediagenda-devs)

pvc() { # nom classe taille
  local classe_ligne=""
  [[ "$2" == "-" ]] || classe_ligne="  storageClassName: \"$2\""
  cat <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $1, namespace: $ns}
spec:
  accessModes: ["ReadWriteOnce"]
$classe_ligne
  resources: {requests: {storage: $3}}
YAML
}
essai() { echo "== $1"; shift; "$@" 2>&1 | sed 's/^/   /'; }

essai "PVC de 20 Gio"              kubectl create "${qui[@]}" --dry-run=server -f - < <(pvc e20-gros ceph-rbd 20Gi)
essai "PVC sur ceph-rbd-retain"    kubectl create "${qui[@]}" --dry-run=server -f - < <(pvc e20-retain ceph-rbd-retain 1Gi)
essai "PVC sans classe"            kubectl create "${qui[@]}" --dry-run=server -f - < <(pvc e20-sans - 1Gi)
essai "PVC classe vide"            kubectl create "${qui[@]}" --dry-run=server -f - < <(pvc e20-vide "" 1Gi)
essai "Annotation de l'espace"     kubectl annotate "${qui[@]}" --dry-run=server --overwrite namespace "$ns" medisphere.internal/classes-stockage=ceph-rbd,cephfs,ceph-rbd-retain
# Le onzième PVC et le sixième instantané se testent en créant réellement les objets (le quota
# compte ce qui existe) : voir le corrigé.
