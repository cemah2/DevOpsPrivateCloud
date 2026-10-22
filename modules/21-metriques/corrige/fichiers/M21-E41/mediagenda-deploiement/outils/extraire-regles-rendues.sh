#!/bin/sh
# outils/extraire-regles-rendues.sh — mediagenda/deploiement (M21-E41, INC-4841).
# Lit les manifestes RENDUS (rendu/<overlay>.yaml, produits par « kustomize build overlays/<overlay> »)
# et, pour chaque PrometheusRule :
#   - vérifie qu'elle porte l'étiquette de sélection de Prometheus (sinon elle ne serait jamais chargée,
#     sans aucune erreur nulle part) ;
#   - extrait ses groupes dans build/regles/<overlay>-<nom>.yml, que « promtool check rules » sait lire.
# POSIX sh + yq v4 (mikefarah). Usage : sh outils/extraire-regles-rendues.sh rendu/*.yaml
set -eu
cle=medisphere.internal/supervision
valeur=oui
mkdir -p build/regles
erreurs=0 n=0
for f in "$@"; do
  o=$(basename "$f" .yaml)
  for nom in $(yq eval-all 'select(.kind == "PrometheusRule") | .metadata.name' "$f"); do
    v=$(N="$nom" K="$cle" yq eval-all 'select(.kind == "PrometheusRule" and .metadata.name == strenv(N)) | .metadata.labels[strenv(K)] // ""' "$f")
    if [ "$v" != "$valeur" ]; then
      echo "KO  $o : PrometheusRule $nom sans l'étiquette $cle=$valeur (Prometheus l'ignorerait)" >&2
      erreurs=$((erreurs + 1))
    fi
    N="$nom" yq eval-all 'select(.kind == "PrometheusRule" and .metadata.name == strenv(N)) | {"groups": .spec.groups}' "$f" \
      > "build/regles/$o-$nom.yml"
    n=$((n + 1))
  done
done
echo "règles : $n fichier(s) extrait(s) dans build/regles/"
[ "$erreurs" -eq 0 ]
