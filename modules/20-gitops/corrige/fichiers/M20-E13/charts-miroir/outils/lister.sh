#!/bin/sh
# outils/lister.sh — contrôle charts.yaml et en tire charts.tsv (nom, dépôt, version, empreinte),
# lu par outils/recopier.sh (M20-E13). POSIX sh + yq 4 (mikefarah) : tourne dans l'image mikefarah/yq.
# Code 1 si une entrée est incomplète, sans version exacte ou sans empreinte SHA-256.
set -eu

f="${1:-charts.yaml}"
sortie="${2:-charts.tsv}"

yq -e '.charts | length > 0' "$f" >/dev/null || { echo "ERREUR $f : liste « charts » vide ou absente" >&2; exit 1; }

# Contrôles entrée par entrée : yq -e échoue si au moins une entrée ne respecte pas la règle.
yq -e '[.charts[] | select((.nom // "") | test("^[a-z0-9][a-z0-9-]*$") | not)] | length == 0' "$f" >/dev/null \
  || { echo "ERREUR $f : nom absent ou invalide" >&2; exit 1; }
yq -e '[.charts[] | select((.version // "" | tostring) | test("^[0-9]+\.[0-9]+\.[0-9]+$") | not)] | length == 0' "$f" >/dev/null \
  || { echo "ERREUR $f : version absente ou non exacte (X.Y.Z attendu)" >&2; exit 1; }
yq -e '[.charts[] | select((.empreinte // "") | test("^sha256:[a-f0-9]{64}$") | not)] | length == 0' "$f" >/dev/null \
  || { echo "ERREUR $f : empreinte absente ou invalide (sha256:<64 hexa>)" >&2; exit 1; }
yq -e '[.charts[] | select((.depot // "") | test("^(https|oci)://") | not)] | length == 0' "$f" >/dev/null \
  || { echo "ERREUR $f : dépôt amont absent ou non https/oci" >&2; exit 1; }
yq -e '(.charts | map(.nom) | length) == (.charts | map(.nom) | unique | length)' "$f" >/dev/null \
  || { echo "ERREUR $f : un chart apparaît deux fois" >&2; exit 1; }

yq -r '.charts[] | [.nom, .depot, (.version | tostring), .empreinte] | @tsv' "$f" >"$sortie"
echo "$(wc -l <"$sortie") chart(s) à recopier :"
cat "$sortie"
