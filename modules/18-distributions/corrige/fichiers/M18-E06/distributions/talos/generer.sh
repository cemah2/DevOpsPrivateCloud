#!/usr/bin/env bash
# talos/generer.sh — génère les configurations machine de talos-essai HORS du dépôt (M18-E05, E06).
#
#   admin@adm01:~/src/distributions$ talos/generer.sh
#
# Entrées : talos/versions.env, le bundle de secrets (~/.config/workbook/m18/talos-secrets.yaml,
# créé une fois par « talosctl gen secrets »), et les patches du dépôt :
#   talos/patches/commun/*.yaml        tous les nœuds
#   talos/patches/controlplane/*.yaml  nœuds de contrôle
#   talos/patches/worker/*.yaml        travailleurs
# et (E06) un document TrustedRootsConfig construit À LA VOLÉE depuis la racine MédiSphère du
# poste (MEDISPHERE_CA) : on ne recopie pas le certificat dans le dépôt, on le lit là où ca_lab l'a mis.
# Les patches PROPRES À UN NŒUD (talos/noeuds/<nom>.yaml) s'ajoutent à l'application (appliquer.sh).
# Sortie : ~/.cache/m18/talos/ (700) : controlplane.yaml, worker.yaml (ils contiennent les clés du
# cluster : jamais dans un dépôt), talosconfig (copié dans ~/.config/workbook/m18/ s'il n'y est pas).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="${TALOS_SECRETS:-$HOME/.config/workbook/m18/talos-secrets.yaml}"
SORTIE="${TALOS_SORTIE:-$HOME/.cache/m18/talos}"
TALOSCONFIG_CIBLE="${TALOSCONFIG_CIBLE:-$HOME/.config/workbook/m18/talosconfig}"
MEDISPHERE_CA="${MEDISPHERE_CA:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

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

# Racine MédiSphère (cache Harbor en TLS) : document TrustedRootsConfig, nom medisphere-root-ca.
if [[ -r "$MEDISPHERE_CA" ]]; then
  racine="$SORTIE/racine-medisphere.yaml"
  {
    printf 'apiVersion: v1alpha1\nkind: TrustedRootsConfig\nname: medisphere-root-ca\ncertificates: |\n'
    sed 's/^/  /' "$MEDISPHERE_CA"
  } > "$racine"
  args+=(--config-patch "@$racine")
else
  echo "Racine MédiSphère introuvable ($MEDISPHERE_CA) : les nœuds ne pourront pas joindre le cache Harbor en TLS." >&2
  exit 1
fi

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
