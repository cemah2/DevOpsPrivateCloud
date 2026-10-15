#!/usr/bin/env bash
# talos/monter.sh — montée de version de talos-essai (M18-E06, CHG-1906).
#
#   talos/monter.sh talos --essai     montre le plan (versions actuelles, image visée), ne change rien
#   talos/monter.sh talos             Talos : nœud de contrôle, puis travailleurs, UN PAR UN
#   talos/monter.sh kubernetes --essai   talosctl upgrade-k8s --dry-run
#   talos/monter.sh kubernetes           talosctl upgrade-k8s
#
# Les versions visées sont celles de versions.env (MR d'abord). Après chaque nœud, on attend la
# santé du cluster avant de passer au suivant ; à la moindre erreur, on s'arrête (set -e).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TALOSCONFIG="${TALOSCONFIG:-$HOME/.config/workbook/m18/talosconfig}"
# shellcheck source=versions.env
source "$ICI/versions.env"

quoi="${1:?usage : $0 talos|kubernetes [--essai]}"
essai="${2:-}"
image="factory.talos.dev/nocloud-installer/${TALOS_SCHEMA_ID}:${TALOS_VERSION}"
cp="$(awk '$3 == "controlplane" {print $2; exit}' "$ICI/noeuds.txt")"
mapfile -t ordre < <(awk '!/^#/ && NF == 3 {print ($3 == "controlplane" ? 0 : 1), $2}' "$ICI/noeuds.txt" | sort -k1,1n -k2 | cut -d' ' -f2)

case "$quoi" in
  talos)
    for ip in "${ordre[@]}"; do
      actuelle="$(talosctl --nodes "$ip" version 2>/dev/null | awk '/Tag:/ {t=$2} END {print t}')"
      echo "== $ip : Talos ${actuelle:-?} → $TALOS_VERSION ($image)"
      [[ "$actuelle" == "$TALOS_VERSION" ]] && { echo "   déjà à jour"; continue; }
      [[ "$essai" == "--essai" ]] && continue
      # Draine le nœud (défaut), installe sur la partition inactive (schéma A/B), redémarre.
      talosctl --nodes "$ip" upgrade --image "$image" --wait
      talosctl --nodes "$cp" health --wait-timeout 10m
    done
    ;;
  kubernetes)
    if [[ "$essai" == "--essai" ]]; then
      talosctl --nodes "$cp" upgrade-k8s --to "$KUBERNETES_VERSION" --dry-run
    else
      talosctl --nodes "$cp" upgrade-k8s --to "$KUBERNETES_VERSION"
      talosctl --nodes "$cp" health --wait-timeout 10m
    fi
    ;;
  *)
    echo "usage : $0 talos|kubernetes [--essai]" >&2; exit 1 ;;
esac
