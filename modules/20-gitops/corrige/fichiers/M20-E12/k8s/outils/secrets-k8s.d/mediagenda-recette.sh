#!/usr/bin/env bash
# plateforme/k8s — outils/secrets-k8s.d/mediagenda-recette.sh (M20-E12) : composant « mediagenda-recette »
# de secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier mediagenda-recette). Logique commune :
# mediagenda-commun.sh ; Vault : secrets/mediagenda-recette.yml.
# shellcheck source=SCRIPTDIR/mediagenda-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/mediagenda-commun.sh"
secrets_mediagenda_recette_appliquer() { secrets_mediagenda_appliquer mediagenda-recette; }
secrets_mediagenda_recette_verifier() { secrets_mediagenda_verifier mediagenda-recette; }
