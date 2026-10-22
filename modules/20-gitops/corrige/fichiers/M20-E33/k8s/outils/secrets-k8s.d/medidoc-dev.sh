#!/usr/bin/env bash
# plateforme/k8s — outils/secrets-k8s.d/medidoc-dev.sh (M20-E33) : composant « medidoc-dev »
# de secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier medidoc-dev). Logique commune :
# medidoc-commun.sh ; Vault : secrets/medidoc-dev.yml.
# shellcheck source=SCRIPTDIR/medidoc-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/medidoc-commun.sh"
secrets_medidoc_dev_appliquer() { secrets_medidoc_appliquer medidoc-dev; }
secrets_medidoc_dev_verifier() { secrets_medidoc_verifier medidoc-dev; }
