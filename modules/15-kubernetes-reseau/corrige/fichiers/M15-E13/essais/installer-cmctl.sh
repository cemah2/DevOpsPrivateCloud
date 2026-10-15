#!/usr/bin/env bash
# ~/m15/e13/installer-cmctl.sh — cmctl (CLI de cert-manager, dépôt cert-manager/cmctl) sur adm01.
# Version épinglée ; l'empreinte se relève sur la page de la publication (fichier de sommes de
# contrôle) et se colle ici APRÈS vérification de sa signature si elle est publiée.
# ⚠️ Nom exact de l'archive à vérifier sur la page de la version (cmctl_linux_amd64.tar.gz attendu).
set -euo pipefail
version="v2.6.1"
empreinte="<SHA256-RELEVÉE-SUR-LA-PAGE-DE-PUBLICATION>"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSLo "$tmp/cmctl.tar.gz" "https://github.com/cert-manager/cmctl/releases/download/${version}/cmctl_linux_amd64.tar.gz"
echo "${empreinte}  $tmp/cmctl.tar.gz" | sha256sum -c -
tar -xzf "$tmp/cmctl.tar.gz" -C "$tmp" cmctl
install -m 755 "$tmp/cmctl" ~/.local/bin/cmctl
cmctl version --client
