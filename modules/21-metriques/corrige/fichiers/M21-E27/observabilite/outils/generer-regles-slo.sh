#!/bin/sh
# outils/generer-regles-slo.sh — produit, avec « pyrra generate », les règles Prometheus des SLO de
# slo/ dans build/slo/ (une par SLO, même nom de fichier), pour les tests unitaires de la CI
# (M21-E27, PLAT-2227). build/ est ignoré par Git (.gitignore d'E14). Même version de Pyrra que l'opérateur (image du cache ghcr de Harbor).
# Avertissement attendu : « namespace must be set » (l'espace est posé par kustomize, pas dans les
# fichiers) ; sans effet sur les règles produites.
# Ce rendu n'est PAS appliqué : dans le cluster, c'est l'opérateur Pyrra qui écrit les PrometheusRule.
set -eu
mkdir -p build/slo
for f in slo/*.yaml; do
  [ "$(basename "$f")" = kustomization.yaml ] && continue
  printf '%s\n' "$f"
done > /tmp/slo-liste
# pyrra generate lit un motif (glob) ; on lui donne un dossier qui ne contient que les SLO.
mkdir -p /tmp/slo-entrees
while read -r f; do cp "$f" /tmp/slo-entrees/; done < /tmp/slo-liste
pyrra generate --config-files='/tmp/slo-entrees/*.yaml' --prometheus-folder=build/slo/
ls build/slo
