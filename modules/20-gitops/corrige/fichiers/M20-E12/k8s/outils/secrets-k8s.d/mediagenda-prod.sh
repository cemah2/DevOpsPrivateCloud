#!/usr/bin/env bash
# plateforme/k8s — outils/secrets-k8s.d/mediagenda-prod.sh (M20-E12) : composant « mediagenda-prod »
# de secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier mediagenda-prod). Logique commune :
# mediagenda-commun.sh ; Vault : secrets/mediagenda-prod.yml.
# shellcheck source=SCRIPTDIR/mediagenda-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/mediagenda-commun.sh"
secrets_mediagenda_prod_appliquer() { secrets_mediagenda_appliquer mediagenda-prod; }
secrets_mediagenda_prod_verifier() { secrets_mediagenda_verifier mediagenda-prod; }
