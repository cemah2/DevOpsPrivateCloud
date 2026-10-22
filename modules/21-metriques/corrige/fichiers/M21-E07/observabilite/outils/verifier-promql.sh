#!/bin/sh
# outils/verifier-promql.sh — vérifie la SYNTAXE des requêtes des fichiers .promql (M21-E07).
# Format : une requête par bloc, blocs séparés par au moins une ligne vide, commentaires en « # ».
# Chaque requête est passée à « promtool --experimental promql format » (analyse sans serveur).
# Usage : outils/verifier-promql.sh requetes/*.promql      (POSIX sh : tourne dans l'image prometheus)
set -eu
command -v promtool >/dev/null 2>&1 || { echo "promtool introuvable" >&2; exit 2; }
[ "$#" -ge 1 ] || { echo "usage : $0 fichier.promql…" >&2; exit 2; }
erreurs=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for f in "$@"; do
  # Découpe en blocs : un fichier par requête (commentaires retirés, lignes jointes par un espace).
  rm -f "$tmp"/q.*
  awk -v d="$tmp" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { if (q != "") { n++; print q > (d "/q." n); close(d "/q." n); q = "" } next }
    { q = (q == "" ? $0 : q " " $0) }
    END { if (q != "") { n++; print q > (d "/q." n); close(d "/q." n) } }
  ' "$f"
  nb=0
  for q in "$tmp"/q.*; do
    [ -e "$q" ] || continue
    nb=$((nb + 1))
    if ! promtool --experimental promql format "$(cat "$q")" >/dev/null 2>"$tmp/err"; then
      echo "KO $f, requête $nb : $(cat "$q")" >&2
      sed 's/^/   /' "$tmp/err" >&2
      erreurs=$((erreurs + 1))
    fi
  done
  echo "$f : $nb requête(s)"
done
[ "$erreurs" -eq 0 ] || { echo "$erreurs requête(s) invalide(s)" >&2; exit 1; }
