#!/usr/bin/env bash
# manifeste-paquets.sh — liste des paquets installés dans l'image (M03-E10).
# Lancé par Packer (en root) APRÈS la personnalisation et AVANT preparer-clonage.sh ;
# écrit $SORTIE (défaut /tmp/paquets.txt), rapatrié sur la machine de build par un
# provisioner « file » (direction = "download") dans manifests/<image>-paquets.txt.
# Format : « nom<TAB>version », trié, une ligne par paquet : deux images au contenu
# identique ont la même empreinte SHA-256.
set -euo pipefail

sortie="${SORTIE:-/tmp/paquets.txt}"
if command -v dpkg-query >/dev/null; then
  dpkg-query -W -f '${db:Status-Abbrev}\t${Package}\t${Version}\n' \
    | awk -F '\t' '$1 ~ /^ii/ { print $2 "\t" $3 }' | LC_ALL=C sort > "$sortie"
else
  rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | LC_ALL=C sort > "$sortie"
fi
chmod 644 "$sortie"
printf 'paquets : %s, sha256 %s\n' "$(wc -l < "$sortie")" "$(sha256sum "$sortie" | cut -d' ' -f1)"
