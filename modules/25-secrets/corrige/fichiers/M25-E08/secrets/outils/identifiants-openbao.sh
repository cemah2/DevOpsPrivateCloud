#!/usr/bin/env bash
# identifiants-openbao.sh — identifiants à recopier dans tofu/imports.tf (M25-E08). LECTURE SEULE.
# Utilise le jeton de la session (bao login -method=oidc) ; n'affiche aucune valeur de secret.
# Usage : outils/identifiants-openbao.sh
set -euo pipefail

command -v bao >/dev/null || { echo "identifiants-openbao : CLI bao introuvable" >&2; exit 2; }
: "${BAO_ADDR:?BAO_ADDR non défini (https://openbao.par1.medisphere.internal:8200)}"

echo "# Montages et méthodes (importés par leur chemin)"
bao secrets list -format=json | jq -r 'to_entries[] | select(.value.type == "kv") | "  moteur  \(.key)  version \(.value.options.version // "1")"'
bao auth list -format=json | jq -r 'to_entries[] | "  méthode \(.key)  type \(.value.type)  accessor \(.value.accessor)"'

echo "# Rôles"
bao list -format=json auth/approle/role 2>/dev/null | jq -r '.[] | "  auth/approle/role/\(.)"' || true
bao list -format=json auth/oidc/role 2>/dev/null | jq -r '.[] | "  auth/oidc/role/\(.)"' || true

echo "# Politiques (importées par leur nom)"
bao policy list | grep -Ev '^(default|root)$' | sed 's/^/  /'

echo "# Groupes d'identité : nom, identifiant du groupe, identifiant de l'alias"
for g in $(bao list -format=json identity/group/name 2>/dev/null | jq -r '.[]'); do
  bao read -format=json "identity/group/name/$g" \
    | jq -r '"  \(.data.name)  type=\(.data.type)  groupe=\(.data.id)  alias=\(.data.alias.id // "aucun")"'
done
