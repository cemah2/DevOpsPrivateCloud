#!/usr/bin/env bash
# capi/pivot.sh — déplace capi-essai du cluster d'amorçage (kind) vers k3s01 (M18-E12, PLAT-1912).
#
#   admin@adm01:~/src/distributions$ capi/pivot.sh --essai    clusterctl move --dry-run
#   admin@adm01:~/src/distributions$ capi/pivot.sh            pivot réel
#
# Préalables (vérifiés ici) : les fournisseurs sont installés sur la cible aux MÊMES versions
# (capi/init.sh) ; le cluster source est stable (pas de machine en cours de création ou de
# suppression : clusterctl move le suppose, documentation de clusterctl).
set -euo pipefail

SOURCE="${SOURCE:-$HOME/.config/workbook/m18/kind-gestion.kubeconfig}"
CIBLE="${CIBLE:-$HOME/.config/workbook/m18/k3s01.kubeconfig}"
ESPACE=capi-essai
SAUVEGARDE="${SAUVEGARDE:-$HOME/m18/e12/avant-pivot}"

versions() { # versions KUBECONFIG — « fournisseur version » triés
  kubectl --kubeconfig "$1" get providers.clusterctl.cluster.x-k8s.io -A \
    -o jsonpath='{range .items[*]}{.providerName}{" "}{.version}{"\n"}{end}' | sort
}

echo "== Fournisseurs : source et cible doivent être identiques"
diff <(versions "$SOURCE") <(versions "$CIBLE") || { echo "Versions différentes : lance capi/init.sh sur la cible." >&2; exit 1; }

echo "== Machines de la source : aucune en cours de création ou de suppression"
phases="$(kubectl --kubeconfig "$SOURCE" -n "$ESPACE" get machines -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | sort -u)"
[[ "$phases" == "Running" ]] || { echo "Phases des machines : $phases (attendre Running partout)" >&2; exit 1; }

if [[ "${1:-}" == "--essai" ]]; then
  clusterctl move --kubeconfig "$SOURCE" --to-kubeconfig "$CIBLE" -n "$ESPACE" --dry-run -v 3
  exit 0
fi

echo "== Copie de sécurité des objets (contient des Secrets en clair : dossier 700, à effacer ensuite)"
install -d -m 700 "$SAUVEGARDE"
clusterctl move --kubeconfig "$SOURCE" -n "$ESPACE" --to-directory "$SAUVEGARDE"

echo "== Pivot"
clusterctl move --kubeconfig "$SOURCE" --to-kubeconfig "$CIBLE" -n "$ESPACE"

echo "== État sur la cible"
clusterctl describe cluster "$ESPACE" -n "$ESPACE" --kubeconfig "$CIBLE"
