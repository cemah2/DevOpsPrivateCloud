#!/usr/bin/env bash
# publier.sh — publie les fichiers de démarrage du projet sur pxe01 (M11-E03 ; rendu NetBox : M11-E06).
#
#   outils/publier.sh [--simulation] [hôte]        (hôte par défaut : pxe01)
#
# Ce qui est publié (et SEULEMENT cela : le reste de /srv/http appartient au rôle Ansible « pxe ») :
#   ipxe/boot.ipxe            → /srv/http/boot.ipxe
#   ipxe/  preseed/  kickstart/ (+ rendu/http/… s'il existe) → /srv/http/{ipxe,preseed,kickstart}/
# Dans ces trois dossiers, ce qui n'est plus dans le dépôt (ou le rendu) est SUPPRIMÉ sur pxe01 :
# un script iPXE d'une machine retirée de NetBox ne doit pas survivre.
# Prérequis : SSH vers l'hôte (certificat d'utilisateur, M06-E20) et sudo sans mot de passe (admin).
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulation=()
if [[ "${1:-}" == "--simulation" ]]; then
  simulation=(--dry-run)
  shift
fi
hote="${1:-pxe01}"
dossiers=(ipxe preseed kickstart)

erreur() { printf 'publier.sh : %s\n' "$*" >&2; exit 1; }

[[ -f "$racine/ipxe/boot.ipxe" ]] || erreur "ipxe/boot.ipxe introuvable dans $racine"

# Dossier de publication temporaire : fichiers du dépôt, puis rendu (qui l'emporte en cas de doublon).
publication="$(mktemp -d)"
trap 'rm -rf "$publication"' EXIT
for d in "${dossiers[@]}"; do
  install -d -m 755 "$publication/$d"
  if [[ -d "$racine/$d" ]]; then
    find "$racine/$d" -maxdepth 1 -type f ! -name 'boot.ipxe' ! -name '.*' -exec install -m 644 -t "$publication/$d" {} +
  fi
  if [[ -d "$racine/rendu/http/$d" ]]; then
    find "$racine/rendu/http/$d" -maxdepth 1 -type f -exec install -m 644 -t "$publication/$d" {} +
  fi
done
install -m 644 "$racine/ipxe/boot.ipxe" "$publication/boot.ipxe"

# Garde-fous : chaque script iPXE commence par #!ipxe ; aucun mot de passe en clair.
while IFS= read -r -d '' f; do
  [[ "$(head -n 1 "$f")" == "#!ipxe" ]] || erreur "$(basename "$f") ne commence pas par #!ipxe"
done < <(find "$publication" -name '*.ipxe' -print0)
if grep -RInE 'passwd/(root|user)-password(-again)? +password|--plaintext|^rootpw +[^-]' "$publication" >/dev/null; then
  erreur "mot de passe en clair détecté : publication refusée"
fi

# rsync côté pxe01 en root (sudo -n) : fichiers root:root, lisibles par nginx.
options=(--recursive --checksum --delete '--chmod=D755,F644' --chown=root:root
         --rsync-path='sudo -n rsync' --itemize-changes "${simulation[@]}")
for d in "${dossiers[@]}"; do
  rsync "${options[@]}" "$publication/$d/" "$hote:/srv/http/$d/"
done
rsync "${options[@]}" "$publication/boot.ipxe" "$hote:/srv/http/boot.ipxe"

if [[ ${#simulation[@]} -gt 0 ]]; then
  echo "Simulation : rien n'a été publié sur $hote."
else
  echo "Publié sur $hote : boot.ipxe, ${dossiers[*]}."
fi
