#!/usr/bin/env bash
# plateforme/k8s — outils/secrets-k8s.d/medidoc-recette.sh (M20-E33) : composant « medidoc-recette »
# de secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier medidoc-recette). Logique commune :
# medidoc-commun.sh ; Vault : secrets/medidoc-recette.yml.
# shellcheck source=SCRIPTDIR/medidoc-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/medidoc-commun.sh"
secrets_medidoc_recette_appliquer() { secrets_medidoc_appliquer medidoc-recette; }
secrets_medidoc_recette_verifier() { secrets_medidoc_verifier medidoc-recette; }
