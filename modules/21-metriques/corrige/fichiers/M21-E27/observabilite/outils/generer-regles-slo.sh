#!/bin/sh
# outils/generer-regles-slo.sh — produit, avec « pyrra generate », les règles Prometheus des SLO de
# slo/ dans build/slo/ (une par SLO, même nom de fichier), pour les tests unitaires de la CI
# (M21-E27, PLAT-2227). build/ est ignoré par Git (.gitignore d'E14). Même version de Pyrra que l'opérateur (image du cache ghcr de Harbor).
# Avertissement attendu : « namespace must be set » (l'espace est posé par kustomize, pas dans les
# fichiers) ; sans effet sur les règles produites.
# Ce rendu n'est PAS appliqué : dans le cluster, c'est l'opérateur Pyrra qui écrit les PrometheusRule.
set -eu
rm -rf build/slo
mkdir -p build/slo
# pyrra generate lit un motif (glob) : on lui donne un dossier temporaire, NEUF à chaque passage,
# qui ne contient que les SLO (ni la kustomization, ni un SLO d'essai retiré depuis).
entrees="$(mktemp -d)"
trap 'rm -rf "$entrees"' EXIT
for f in slo/*.yaml; do
  [ "$(basename "$f")" = kustomization.yaml ] && continue
  cp "$f" "$entrees/"
done
pyrra generate --config-files="$entrees/*.yaml" --prometheus-folder=build/slo/
ls build/slo
