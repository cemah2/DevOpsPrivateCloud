#!/usr/bin/env bash
# talos/generer.sh — génère les configurations machine de talos-essai HORS du dépôt (M18-E05).
#
#   admin@adm01:~/src/distributions$ talos/generer.sh
#
# Entrées : talos/versions.env, le bundle de secrets (~/.config/workbook/m18/talos-secrets.yaml,
# créé une fois par « talosctl gen secrets »), et les patches du dépôt :
#   talos/patches/commun/*.yaml        tous les nœuds
#   talos/patches/controlplane/*.yaml  nœuds de contrôle
#   talos/patches/worker/*.yaml        travailleurs
# Les patches PROPRES À UN NŒUD (talos/noeuds/<nom>.yaml) s'ajoutent à l'application (appliquer.sh).
# Sortie : ~/.cache/m18/talos/ (700) : controlplane.yaml, worker.yaml (ils contiennent les clés du
# cluster : jamais dans un dépôt), talosconfig (copié dans ~/.config/workbook/m18/ s'il n'y est pas).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="${TALOS_SECRETS:-$HOME/.config/workbook/m18/talos-secrets.yaml}"
SORTIE="${TALOS_SORTIE:-$HOME/.cache/m18/talos}"
TALOSCONFIG_CIBLE="${TALOSCONFIG_CIBLE:-$HOME/.config/workbook/m18/talosconfig}"

# shellcheck source=versions.env
source "$ICI/versions.env"

[[ -r "$SECRETS" ]] || { echo "Bundle de secrets illisible : $SECRETS (talosctl gen secrets -o …)" >&2; exit 1; }
[[ "$(stat -c %a "$SECRETS")" == 600 ]] || { echo "$SECRETS doit être en 600" >&2; exit 1; }
command -v talosctl >/dev/null || { echo "talosctl absent (rôle outils_distributions)" >&2; exit 1; }

install -d -m 700 "$SORTIE"
rm -f "$SORTIE/controlplane.yaml" "$SORTIE/worker.yaml" "$SORTIE/talosconfig"

args=(
  "$TALOS_CLUSTER" "$TALOS_ENDPOINT"
  --with-secrets "$SECRETS"
  --kubernetes-version "$KUBERNETES_VERSION"
  --install-image "factory.talos.dev/nocloud-installer/${TALOS_SCHEMA_ID}:${TALOS_VERSION}"
  --with-docs=false --with-examples=false
  --output "$SORTIE"
)
shopt -s nullglob
for p in "$ICI"/patches/commun/*.yaml; do args+=(--config-patch "@$p"); done
for p in "$ICI"/patches/controlplane/*.yaml; do args+=(--config-patch-control-plane "@$p"); done
for p in "$ICI"/patches/worker/*.yaml; do args+=(--config-patch-worker "@$p"); done
shopt -u nullglob

talosctl gen config "${args[@]}"
chmod 600 "$SORTIE"/*.yaml "$SORTIE/talosconfig"

# Validation avant tout envoi : une configuration refusée ici ne touche aucun nœud.
talosctl validate --mode cloud --config "$SORTIE/controlplane.yaml"
talosctl validate --mode cloud --config "$SORTIE/worker.yaml"

if [[ ! -e "$TALOSCONFIG_CIBLE" ]]; then
  install -m 600 "$SORTIE/talosconfig" "$TALOSCONFIG_CIBLE"
  echo "talosconfig installé dans $TALOSCONFIG_CIBLE (règle points d'accès et nœuds : talosctl config endpoint/node)."
fi
echo "Configurations générées dans $SORTIE (Talos $TALOS_VERSION, Kubernetes $KUBERNETES_VERSION)."
