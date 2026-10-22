#!/usr/bin/env bash
# qui-ecrit.sh — qui modifie cet objet ? (M20-E39). Lecture seule.
#
#   outils/qui-ecrit.sh mediagenda-dev deployment mediagenda
#
# 1. gestionnaires de champs (managedFields) : manager, opération, sous-ressource, date, champs
#    de premier niveau possédés ;
# 2. Applications d'Argo CD qui déclarent l'objet (status.resources) et annotation de suivi actuelle ;
# 3. HPA qui visent l'objet ;
# 4. comptes de service d'AUTRES espaces qui ont des droits dans l'espace (RoleBindings) : la piste
#    d'une tâche planifiée ou d'un outil qui écrit de l'extérieur.
# Pour aller plus loin : journal d'audit de l'API (M14-E27), filtré sur l'objet et le verbe patch.
set -euo pipefail

ns="${1:?usage : $0 ESPACE TYPE NOM}"
type="${2:?}"
nom="${3:?}"

echo "== Gestionnaires de champs de $type/$nom ($ns)"
kubectl -n "$ns" get "$type" "$nom" -o json --show-managed-fields | jq -r '
  .metadata.managedFields[] | [.manager, .operation, (.subresource // "-"), .time,
    ((.fieldsV1 // {}) | [paths(type == "object") | select(length == 2) | map(sub("^f:"; "")) | join(".")] | unique | join(" "))] | @tsv'

echo
echo "== Annotation de suivi et Applications qui déclarent l'objet"
kubectl -n "$ns" get "$type" "$nom" -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}'
kind="$(kubectl -n "$ns" get "$type" "$nom" -o jsonpath='{.kind}')"
kubectl -n argocd get applications.argoproj.io -o json | jq -r --arg k "$kind" --arg n "$nom" --arg ns "$ns" '
  .items[] | select(any(.status.resources[]?; .kind == $k and .name == $n and (.namespace // "") == $ns))
  | "\(.metadata.name)\t\(.status.sync.status)\t\([.status.conditions[]?.type] | join(","))"'

echo
echo "== HPA de l'espace"
kubectl -n "$ns" get hpa -o custom-columns=NOM:.metadata.name,CIBLE:.spec.scaleTargetRef.name,MIN:.spec.minReplicas,MAX:.spec.maxReplicas --no-headers 2>/dev/null || true

echo
echo "== Comptes de service d'autres espaces avec des droits dans $ns"
kubectl -n "$ns" get rolebindings -o json | jq -r --arg ns "$ns" '
  .items[] | . as $rb | .subjects[]? | select(.kind == "ServiceAccount" and (.namespace // $ns) != $ns)
  | "\($rb.metadata.name)\t→ \(.namespace)/\(.name)\t(\($rb.roleRef.kind)/\($rb.roleRef.name))"'
