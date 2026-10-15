#!/usr/bin/env bash
# outils/schemas-crd.sh — plateforme/k8s (M15-E23). Convertit les CRD du réseau en schémas JSON pour
# kubeconform (ci/schemas/crd/<groupe>/<Kind>_<version>.json), depuis le cluster (CRD réellement
# installées : c'est ce qu'on veut valider) ou, en CI hors cluster, depuis des fichiers de CRD.
# Usage : outils/schemas-crd.sh [fichier-de-crd.yaml…]   (sans argument : lit le cluster)
set -euo pipefail
cd "$(dirname "$0")/.."
sortie=ci/schemas/crd
mkdir -p "$sortie"
if (( $# )); then src="$(cat "$@")"; else
  src="$(kubectl get crd -o json | jq '.items[] | select(.spec.group | test("(cilium\\.io|gateway\\.networking\\.k8s\\.io|cert-manager\\.io)$"))' | jq -s '.[]')"
fi
yq -o json -I0 'select(.kind == "CustomResourceDefinition")' <<<"$src" 2>/dev/null \
  | jq -c '. as $c | .spec.versions[] | select(.served) | {g: $c.spec.group, k: $c.spec.names.kind, v: .name, s: .schema.openAPIV3Schema}' \
  | while read -r l; do
      g="$(jq -r .g <<<"$l")"; k="$(jq -r '.k | ascii_downcase' <<<"$l")"; v="$(jq -r .v <<<"$l")"
      mkdir -p "$sortie/$g"
      # Mode strict de kubeconform : objets fermés (additionalProperties: false) sauf s'ils sont
      # déclarés ouverts (x-kubernetes-preserve-unknown-fields).
      jq '.s | walk(if type == "object" and .type == "object" and (has("properties")) and (has("additionalProperties") | not) and ((."x-kubernetes-preserve-unknown-fields" // false) | not) then . + {additionalProperties: false} else . end)' \
        <<<"$l" > "$sortie/$g/${k}_${v}.json"
    done
echo "Schémas écrits dans $sortie/"
