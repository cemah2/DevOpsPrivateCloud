#!/usr/bin/env bash
# outils/argocd-derive.sh — plateforme/k8s (M24-E39, INC-5139) : la configuration d'Argo CD en place
# est-elle celle de la release Helmfile « argocd » ?
#
# Compare les clés « data » des ConfigMaps argocd-cm et argocd-rbac-cm RENDUES par la release
# (helmfile template : aucun accès au cluster) à celles du cluster (kubectl get, compte de service qui
# n'a que « get » sur ces deux ConfigMaps : rbac/argocd-derive.yaml). Rien n'est modifié.
# Pourquoi pas « helmfile diff --detailed-exitcode » (M17-E10) : Helm lit l'historique de la release
# dans des Secrets de l'espace argocd ; la CI n'a pas à lire les Secrets d'Argo CD.
#
# Usage : outils/argocd-derive.sh [ENVIRONNEMENT]      (défaut : par1)
# Variables : KUBECONFIG (kubeconfig du compte argocd-derive ; en CI, variable de type fichier).
# Sortie : 0 = identique ; 1 = dérive (différences affichées clé par clé) ; 2 = erreur d'outil.
set -euo pipefail

env="${1:-par1}"
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT

for outil in helmfile kubectl yq diff; do
  command -v "$outil" >/dev/null || { echo "argocd-derive : outil manquant : $outil" >&2; exit 2; }
done

# 1. Rendu de la release (les valeurs ne contiennent aucun secret : clientSecret est une référence).
if ! (cd "$racine" && helmfile -e "$env" -l composant=argocd template --skip-deps) >"$travail/rendu.yaml" 2>"$travail/rendu.err"; then
  echo "argocd-derive : rendu de la release impossible :" >&2
  cat "$travail/rendu.err" >&2
  exit 2
fi

derive=0
for cm in argocd-cm argocd-rbac-cm; do
  # Données rendues, triées par clé ; une clé absente du rendu vaut « absente ».
  CM="$cm" yq -P 'select(.kind == "ConfigMap" and .metadata.name == strenv(CM)) | .data // {} | sort_keys(.)' \
    "$travail/rendu.yaml" >"$travail/$cm.code"
  if ! kubectl -n argocd get configmap "$cm" -o yaml --show-managed-fields >"$travail/$cm.brut" 2>"$travail/$cm.err"; then
    echo "argocd-derive : lecture de argocd/$cm impossible :" >&2
    cat "$travail/$cm.err" >&2
    exit 2
  fi
  yq -P '.data // {} | sort_keys(.)' "$travail/$cm.brut" >"$travail/$cm.cluster"
  if diff -u --label "$cm (release)" --label "$cm (cluster)" "$travail/$cm.code" "$travail/$cm.cluster"; then
    echo "argocd-derive : $cm identique à la release."
  else
    derive=1
    echo "argocd-derive : DÉRIVE de $cm (lignes « + » : présentes dans le cluster, pas dans la release)."
    # Qui a écrit en dernier, et quand (sans Secret, sans valeur).
    yq '.metadata.managedFields[] | "  écrit par " + .manager + " (" + .operation + ") à " + .time' "$travail/$cm.brut" || true
  fi
done

exit "$derive"
