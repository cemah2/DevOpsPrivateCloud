#!/usr/bin/env bash
# ~/m14/e12/julien/generer-demande.sh — ce que Julien lance sur SON poste (simulé ici dans
# ~/m14/e12/julien/ sur adm01). Seul le .csr est transmis à l'équipe Plateforme.
set -euo pipefail
cd "$(dirname "$0")"
umask 077
[[ -e julien.petit.key ]] && { echo "julien.petit.key existe déjà : on ne l'écrase pas." >&2; exit 1; }
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout julien.petit.key \
  -subj "/CN=julien.petit/O=medisphere:mediagenda-devs" \
  -out julien.petit.csr
chmod 600 julien.petit.key
chmod 644 julien.petit.csr
openssl req -in julien.petit.csr -noout -subject
