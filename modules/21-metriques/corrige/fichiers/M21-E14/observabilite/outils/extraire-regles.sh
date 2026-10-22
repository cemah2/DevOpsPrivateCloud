#!/bin/sh
# outils/extraire-regles.sh — plateforme/observabilite (M21-E14, E15).
# Extrait, pour promtool, la « spec » de chaque PrometheusRule de regles/ → build/regles/<fichier>.yml
# (format des fichiers de règles de Prometheus : « groups: … »). La configuration d'Alertmanager
# est extraite par la CI d'E07 (job alertmanager:extraire).
# Usage (racine du dépôt) : outils/extraire-regles.sh      — exige yq v4 (mikefarah).
# POSIX sh : tourne dans l'image mikefarah/yq (Alpine, sans bash) comme sur adm01.
set -eu

sortie=build
rm -rf "$sortie"
mkdir -p "$sortie/regles"

n=0
for f in regles/*.yaml; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in kustomization.yaml) continue ;; esac
  # Un fichier peut contenir plusieurs documents : on ne garde que les PrometheusRule.
  nb="$(yq eval-all '[select(.kind == "PrometheusRule")] | length' "$f")"
  [ "$nb" -gt 0 ] || continue
  cible="$sortie/regles/$(basename "$f" .yaml).yml"
  yq eval-all '[select(.kind == "PrometheusRule") | .spec.groups[]] | {"groups": .}' "$f" > "$cible"
  n=$((n + 1))
done
echo "règles : $n fichier(s) extrait(s) dans $sortie/regles/"

