#!/usr/bin/env bash
# plateforme/k8s — outils/secrets-k8s.d/mediagenda-dev.sh (M20-E12) : composant « mediagenda-dev »
# de secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier mediagenda-dev). Logique commune :
# mediagenda-commun.sh ; Vault : secrets/mediagenda-dev.yml.
# shellcheck source=SCRIPTDIR/mediagenda-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/mediagenda-commun.sh"
secrets_mediagenda_dev_appliquer() { secrets_mediagenda_appliquer mediagenda-dev; }
secrets_mediagenda_dev_verifier() { secrets_mediagenda_verifier mediagenda-dev; }
