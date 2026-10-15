#!/usr/bin/env bash
# k3s/outils/preuve-chiffrement.sh — prouve que les Secrets de k3s01 sont chiffrés dans SQLite (M18-E15).
# Usage (depuis adm01) : k3s/outils/preuve-chiffrement.sh [HÔTE] [CLÉ]
#   défaut : k3s01, /registry/secrets/capi-essai/capi-essai-proxmox
# Méthode : copie COHÉRENTE de la base à chaud (sqlite3 .backup, sans arrêter k3s), lecture de la
# dernière révision de la clé dans la table « kine » de la COPIE, affichage des 20 premiers octets
# seulement (jamais la valeur), effacement de la copie. Exige sqlite3 sur l'hôte.
set -euo pipefail

hote="${1:-k3s01}"
cle="${2:-/registry/secrets/capi-essai/capi-essai-proxmox}"

# shellcheck disable=SC2029  # la clé est expansée ici, volontairement (citée par printf %q)
ssh "$hote" "sudo -n bash -s -- $(printf '%q' "$cle")" <<'DISTANT'
set -euo pipefail
cle="$1"
command -v sqlite3 >/dev/null || { echo "sqlite3 absent : apt-get install sqlite3" >&2; exit 1; }
d="$(mktemp -d)"; chmod 700 "$d"
trap 'rm -rf "$d"' EXIT
sqlite3 /var/lib/rancher/k3s/server/db/state.db ".backup '$d/copie.db'"
# kine : une ligne par révision ; la valeur courante est celle de l'id le plus grand, non supprimée.
sqlite3 "$d/copie.db" "SELECT hex(substr(value, 1, 20)) FROM kine WHERE name = '$cle' AND deleted = 0 ORDER BY id DESC LIMIT 1;" \
  | xxd -r -p | od -c | head -2
DISTANT
printf '%s\n' "Attendu après chiffrement : « k8s:enc:aescbc:v1: » (ou secretbox). Avant : « k8s » suivi d'un octet nul, puis du protobuf."
