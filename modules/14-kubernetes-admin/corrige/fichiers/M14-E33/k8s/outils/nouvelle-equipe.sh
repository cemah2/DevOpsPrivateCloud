#!/usr/bin/env bash
# outils/nouvelle-equipe.sh — plateforme/k8s (M14-E33) : génère l'espace et les liaisons RBAC d'une
# équipe à partir de gabarits/equipe/. Ne touche pas au cluster : relis, ajuste l'enveloppe
# (10-quota.yaml) et le responsable (00-namespace.yaml), puis ouvre la MR.
# Usage : outils/nouvelle-equipe.sh EQUIPE ENV     ex. outils/nouvelle-equipe.sh medinotif dev
set -Eeuo pipefail
equipe="${1:-}"; env="${2:-}"
[[ "$equipe" =~ ^[a-z][a-z0-9]{1,20}$ && "$env" =~ ^(dev|recette|prod)$ ]] \
  || { echo "usage : $0 EQUIPE (minuscules) dev|recette|prod" >&2; exit 2; }
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
g="$racine/gabarits/equipe"
espace="$racine/espaces/$equipe-$env"
rbac="$racine/rbac/40-$equipe-$env.yaml"
[[ ! -e "$espace" && ! -e "$rbac" ]] || { echo "$espace ou $rbac existe déjà" >&2; exit 1; }
mkdir -p "$espace"
for f in 00-namespace 10-quota 20-limites 30-comptes-service; do
  sed -e "s/@EQUIPE@/$equipe/g; s/@ENV@/$env/g" "$g/$f.yaml.tmpl" >"$espace/$f.yaml"
done
sed -e "s/@EQUIPE@/$equipe/g; s/@ENV@/$env/g" "$g/rbac.yaml.tmpl" >"$rbac"
if [[ "$env" != dev ]]; then
  echo "ATTENTION : hors de dev, la liaison medisphere-secrets-edition est à retirer (comme mediagenda-recette)." >&2
fi
echo "Généré : $espace/ et $rbac. Ajuste l'enveloppe et le responsable, puis : outils/secret-tirage.sh $equipe-$env (après application), MR."
