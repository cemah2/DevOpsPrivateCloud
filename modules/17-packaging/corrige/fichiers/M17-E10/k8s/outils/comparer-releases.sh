#!/usr/bin/env bash
# comparer-releases.sh — prépare la reprise des releases existantes par Helmfile (M17-E10).
# Pour chaque release Helm du cluster : version de chart installée, et valeurs FOURNIES (pas les
# valeurs calculées) comparées au fichier de valeurs du dépôt (chemins des modules 14 à 16).
# Lecture seule. Usage : outils/comparer-releases.sh [CONTEXTE]   (défaut : k8s-par1)
set -euo pipefail

contexte="${1:-k8s-par1}"
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

helm --kube-context "$contexte" list -A -o json \
  | jq -r '.[] | [.name, .namespace, .chart, .status] | @tsv' \
  | while IFS=$'\t' read -r nom espace chart statut; do
      printf '== %s (%s) : %s, %s\n' "$nom" "$espace" "$chart" "$statut"
      # Fichier de valeurs de la release, là où les modules 14 à 16 l'ont rangé.
      case "$nom" in
        ceph-csi-rbd)    fichier="$racine/composants/ceph-csi/values-rbd.yaml" ;;
        ceph-csi-cephfs) fichier="$racine/composants/ceph-csi/values-cephfs.yaml" ;;
        cnpg)            fichier="$racine/composants/cloudnative-pg/values.yaml" ;;
        *)               fichier="$racine/composants/$nom/values.yaml" ;;
      esac
      helm --kube-context "$contexte" get values "$nom" -n "$espace" -o yaml >"$tmp/$nom.yaml"
      if [[ ! -f "$fichier" ]]; then
        echo "   pas de $fichier : à créer (valeurs fournies dans $tmp/$nom.yaml, copiées ci-dessous)"
        sed 's/^/   | /' "$tmp/$nom.yaml"
      elif diff -q <(yq -P 'sort_keys(..)' "$fichier") <(yq -P 'sort_keys(..)' "$tmp/$nom.yaml") >/dev/null; then
        echo "   valeurs identiques au dépôt"
      else
        echo "   valeurs DIFFÉRENTES (dépôt → cluster) :"
        diff -u <(yq -P 'sort_keys(..)' "$fichier") <(yq -P 'sort_keys(..)' "$tmp/$nom.yaml") | sed 's/^/   /' || true
      fi
    done
