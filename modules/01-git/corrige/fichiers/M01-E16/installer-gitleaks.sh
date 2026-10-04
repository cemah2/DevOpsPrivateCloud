#!/usr/bin/env bash
# installer-gitleaks.sh — installe le binaire officiel de Gitleaks dans /usr/local/bin (M01-E16).
# Usage : sudo ./installer-gitleaks.sh [VERSION]     (défaut : 8.30.1)
# Vérifie la somme SHA-256 publiée avec la release avant d'installer. Rien n'est installé
# si la vérification échoue. Le paquet Debian (8.16) est trop ancien : ne pas l'utiliser.
set -euo pipefail

version="${1:-8.30.1}"
base="https://github.com/gitleaks/gitleaks/releases/download/v${version}"
archive="gitleaks_${version}_linux_x64.tar.gz"

[[ $EUID -eq 0 ]] || { echo "à lancer avec sudo (écriture dans /usr/local/bin)" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
curl -fsSLO "$base/$archive"
curl -fsSLO "$base/gitleaks_${version}_checksums.txt"
grep " ${archive}\$" "gitleaks_${version}_checksums.txt" | sha256sum -c -
tar -xzf "$archive" gitleaks
install -o root -g root -m 0755 gitleaks /usr/local/bin/gitleaks
/usr/local/bin/gitleaks version
