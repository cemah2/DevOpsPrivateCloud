#!/usr/bin/env bash
# tester-sante.sh — évalue un contrôle de santé Lua d'Argo CD contre un objet RÉEL du cluster, AVANT
# de le livrer (M20-E38). Lecture seule : kubectl get, et « argocd admin settings resource-overrides
# health », qui exécute le Lua localement (aucun appel au serveur Argo CD).
#
#   outils/tester-sante.sh composants/argocd/values-sante.yaml postgresql.cnpg.io Cluster mediagenda-db mediagenda-dev
#
# FICHIER_VALEURS : fichier de valeurs Helm de la release argocd qui contient configs.cm.
#   resource.customizations.health.<groupe>_<Kind> ; le script en tire un argocd-cm minimal.
# À lancer depuis la racine du dépôt plateforme/k8s ; la MR doit montrer la sortie pour au moins un
# objet sain ET un objet en cours de création (phase différente).
set -euo pipefail

valeurs="${1:?usage : $0 FICHIER_VALEURS GROUPE KIND NOM ESPACE}"
groupe="${2:?}"
kind="${3:?}"
nom="${4:?}"
espace="${5:?}"
cle="resource.customizations.health.${groupe}_${kind}"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

K="$cle" yq -e '.configs.cm[strenv(K)]' "$valeurs" >/dev/null ||
  { echo "$valeurs ne contient pas configs.cm.\"$cle\"" >&2; exit 2; }
K="$cle" yq '{"apiVersion": "v1", "kind": "ConfigMap",
  "metadata": {"name": "argocd-cm", "namespace": "argocd"},
  "data": {strenv(K): .configs.cm[strenv(K)]}}' "$valeurs" >"$tmp/argocd-cm.yaml"

kubectl -n "$espace" get "${kind,,}.${groupe}" "$nom" -o yaml >"$tmp/objet.yaml"
printf 'Objet : %s/%s (%s) — phase rapportée par l opérateur : %s\n' "$kind" "$nom" "$espace" \
  "$(yq -r '.status.phase // "?"' "$tmp/objet.yaml")"
echo "--- avec le contrôle proposé"
argocd admin settings resource-overrides health "$tmp/objet.yaml" --argocd-cm-path "$tmp/argocd-cm.yaml" 2>/dev/null
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: argocd-cm\n  namespace: argocd\ndata: {}\n' >"$tmp/vide.yaml"
echo "--- avec le contrôle intégré d'Argo CD (sans personnalisation)"
argocd admin settings resource-overrides health "$tmp/objet.yaml" --argocd-cm-path "$tmp/vide.yaml" 2>/dev/null
