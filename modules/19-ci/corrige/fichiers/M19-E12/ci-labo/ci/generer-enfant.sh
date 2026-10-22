#!/usr/bin/env bash
# ci/generer-enfant.sh — formation/ci-labo (M19-E12) : écrit sur la sortie standard la configuration
# d'un pipeline enfant, avec un job de tests par fichier tests/test_*.py.
# Le YAML produit est validé par GitLab à la création du pipeline enfant : une erreur ici fait
# échouer le job déclencheur (« downstream pipeline can not be created »), pas le job « generer ».
set -euo pipefail

image_uv="registry.par1.medisphere.internal/ghcr/astral-sh/uv:0.12.23-python3.13-trixie-slim@sha256:a6aeb5c166af9f765f9c68e585b5a5148c28f3b8a362f90151cecea88b21a3e2"

cat <<EOF
# Généré par ci/generer-enfant.sh — commit ${CI_COMMIT_SHORT_SHA:-local}
stages: [test]
EOF

n=0
for f in tests/test_*.py; do
  [[ -e "$f" ]] || continue
  nom="$(basename "$f" .py)"
  n=$((n + 1))
  cat <<EOF

tests:${nom}:
  stage: test
  tags: [k8s]
  image: ${image_uv}
  variables:
    UV_CACHE_DIR: \$CI_PROJECT_DIR/.cache/uv
  script:
    - uv sync --locked
    - uv run --no-sync pytest --junitxml=rapport-${nom}.xml ${f}
  artifacts:
    when: always
    expire_in: 1 day
    reports:
      junit: rapport-${nom}.xml
EOF
done

# Un pipeline sans job est refusé : on garde un job témoin si aucun fichier n'a été trouvé.
if ((n == 0)); then
  cat <<'EOF'

aucun-test:
  stage: test
  tags: [k8s]
  image: registry.par1.medisphere.internal/dockerhub/library/busybox:1.37
  script:
    - echo "aucun fichier tests/test_*.py"
EOF
fi
