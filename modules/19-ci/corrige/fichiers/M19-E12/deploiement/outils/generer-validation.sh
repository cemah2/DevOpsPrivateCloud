#!/usr/bin/env bash
# outils/generer-validation.sh — mediagenda/deploiement (M19-E12) : configuration du pipeline ENFANT
# qui valide une nouvelle version du chart sur chaque overlay présent dans overlays/.
# Sortie standard : YAML. Un overlay ajouté au dépôt est validé sans toucher à ce script.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

image="${IMAGE_K8S:?IMAGE_K8S non défini}"
cat <<EOF
# Généré par outils/generer-validation.sh — chart ${CHART_VERSION:-?} (${CHART_DIGEST:-?})
stages: [validation]
EOF
for d in overlays/*/; do
  o="$(basename "$d")"
  [[ -f "$d/kustomization.yaml" ]] || continue
  cat <<EOF

valider:${o}:
  stage: validation
  tags: [k8s]
  image:
    name: ${image}
    entrypoint: [""]
  script:
    - outils/valider-chart.sh ${o}
  artifacts:
    when: always
    paths: [rendus/]
    expire_in: 1 week
EOF
done
