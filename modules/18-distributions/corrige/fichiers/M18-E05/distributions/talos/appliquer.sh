#!/usr/bin/env bash
# talos/appliquer.sh — applique la configuration d'un nœud de talos-essai (M18-E05, E06).
#
#   talos/appliquer.sh <nœud> --maintenance   premier contact (nœud en mode maintenance : --insecure)
#   talos/appliquer.sh <nœud> --essai         dry-run : montre ce qui changerait, n'applique rien
#   talos/appliquer.sh <nœud>                 application normale (mTLS avec le talosconfig)
#
# Configuration envoyée = fichier généré par generer.sh (controlplane.yaml ou worker.yaml selon le
# type du nœud dans noeuds.txt) + patch propre au nœud (noeuds/<nœud>.yaml).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SORTIE="${TALOS_SORTIE:-$HOME/.cache/m18/talos}"
export TALOSCONFIG="${TALOSCONFIG:-$HOME/.config/workbook/m18/talosconfig}"

noeud="${1:?usage : $0 <nœud> [--maintenance|--essai]}"
mode="${2:-}"

read -r _ ip type < <(awk -v n="$noeud" '$1 == n {print $1, $2, $3}' "$ICI/noeuds.txt") || true
[[ -n "${ip:-}" ]] || { echo "Nœud inconnu dans noeuds.txt : $noeud" >&2; exit 1; }
base="$SORTIE/$type.yaml"
[[ -r "$base" ]] || { echo "Configuration absente : $base (lance generer.sh)" >&2; exit 1; }

args=(--nodes "$ip" --file "$base")
[[ -r "$ICI/noeuds/$noeud.yaml" ]] && args+=(--config-patch "@$ICI/noeuds/$noeud.yaml")

case "$mode" in
  --maintenance)
    # Seul usage permis de --insecure (règle 4 du module) : le nœud n'a encore aucune identité.
    # Le canal est chiffré mais non authentifié : on vérifie avant que l'adresse est la bonne VM.
    talosctl apply-config --insecure "${args[@]}" ;;
  --essai)
    talosctl apply-config --dry-run "${args[@]}" ;;
  "")
    talosctl apply-config "${args[@]}" ;;
  *)
    echo "Mode inconnu : $mode" >&2; exit 1 ;;
esac
