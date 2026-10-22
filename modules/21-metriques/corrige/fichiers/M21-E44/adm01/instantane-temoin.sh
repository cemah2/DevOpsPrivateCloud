#!/usr/bin/env bash
# instantane-temoin.sh — M21-E44 : instantané de la TSDB du Prometheus témoin (mon01), copie vers
# adm01, puis suppression de l'instantané sur mon01. N'appelle QUE l'API « snapshot ».
# Prérequis : API d'administration ouverte sur mon01 (supervision_temoin_api_admin: true), SSH vers
# mon01 avec sudo. Usage : instantane-temoin.sh [DOSSIER_DE_DESTINATION]
set -euo pipefail

TEMOIN="${WB_M21_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
HOTE="${WB_M21_MON01:-mon01}"
DONNEES=/var/lib/prometheus/data
DEST="${1:-$HOME/m21/e44/instantane}"

drapeau="$(curl -sf --max-time 10 "$TEMOIN/api/v1/status/flags" | jq -r '.data["web.enable-admin-api"]')"
[[ "$drapeau" == true ]] || { echo "API d'administration fermée sur le témoin : ouvre-la par le rôle d'abord." >&2; exit 1; }
[[ ! -e "$DEST" || -z "$(ls -A "$DEST" 2>/dev/null)" ]] || { echo "$DEST n'est pas vide : choisis un autre dossier." >&2; exit 1; }

nom="$(curl -sf --max-time 60 -XPOST "$TEMOIN/api/v1/admin/tsdb/snapshot" | jq -r '.data.name // empty')"
# Garde-fou : un nom d'instantané a la forme AAAAMMJJTHHMMSSZ-<hexadécimal>.
[[ "$nom" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]+$ ]] || { echo "Réponse inattendue de l'API (nom : « $nom »)." >&2; exit 1; }
echo "Instantané $nom créé sur $HOTE."

install -d -m 700 "$DEST"
# shellcheck disable=SC2029  # le nom est validé ci-dessus ; il est développé côté client volontairement
ssh "$HOTE" "sudo tar -C $DONNEES/snapshots/$nom -cf - ." | tar -C "$DEST" -xf -
echo "Copié dans $DEST : $(du -sh "$DEST" | cut -f1)."

# Suppression de CET instantané seulement (jamais snapshots/ entier, jamais data/).
# shellcheck disable=SC2029
ssh "$HOTE" "sudo rm -rf --one-file-system -- $DONNEES/snapshots/$nom && sudo rmdir --ignore-fail-on-non-empty $DONNEES/snapshots"
echo "Instantané supprimé de $HOTE. Pense à refermer l'API d'administration."
