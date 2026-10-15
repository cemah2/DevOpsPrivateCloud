#!/usr/bin/env bash
# outils/schemas-crd.sh (plateforme/k8s) — M16-E23
# Produit les schémas JSON des CRD utilisées par le dépôt, pour kubeconform (CI). Les CRD sont
# lues dans les charts aux versions du dépôt (helm template --include-crds) et dans les
# manifestes amont épinglés : la CI n'a pas besoin d'accès au cluster.
# Disposition produite : schemas/<groupe>/<kind-minuscule>_<version>.json, que kubeconform lit
# avec -schema-location 'schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'.
#   outils/schemas-crd.sh [DOSSIER]     (défaut : schemas)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
sortie="${1:-schemas}"
travail="$(mktemp -d)"; trap 'rm -rf "$travail"' EXIT

{
  kubectl kustomize composants/snapshot-controller
  helm template v vmware-tanzu/velero --version 12.2.1 --include-crds
  helm template c cnpg/cloudnative-pg --version 0.29.1 --include-crds
  helm template p cnpg/plugin-barman-cloud --version 0.8.1 --include-crds
  curl -fsSL https://raw.githubusercontent.com/cilium/cilium/v1.20.2/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml
} | yq 'select(.kind == "CustomResourceDefinition")' -o=json -I=0 \
  | jq -c '. as $c | .spec.versions[] | select(.served) |
      {groupe: $c.spec.group, kind: ($c.spec.names.kind | ascii_downcase), version: .name,
       schema: (.schema.openAPIV3Schema + {"x-kubernetes-group-version-kind":
                [{group: $c.spec.group, kind: $c.spec.names.kind, version: .name}]})}' \
  > "$travail/crd.jsonl"

n=0
while IFS= read -r ligne; do
  groupe="$(jq -r .groupe <<<"$ligne")"; kind="$(jq -r .kind <<<"$ligne")"; version="$(jq -r .version <<<"$ligne")"
  mkdir -p "$sortie/$groupe"
  jq '.schema' <<<"$ligne" > "$sortie/$groupe/${kind}_${version}.json"
  n=$((n + 1))
done < "$travail/crd.jsonl"
echo "schemas-crd : $n schémas écrits dans $sortie/"
