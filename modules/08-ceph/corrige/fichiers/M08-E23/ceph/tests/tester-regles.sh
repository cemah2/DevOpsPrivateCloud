#!/usr/bin/env bash
# tests/tester-regles.sh — chaque règle maison REJETTE son cas fautif (M08-E23). Une règle qui
# accepterait son cas fautif ne prouverait rien. Pour chaque tests/cas-fautifs/regleN/ : copie de
# specs/, superposition des fichiers du cas, verifier-specs.sh doit échouer sur « règle N ».
# Puis tester-crush.sh doit échouer sur la carte de tests/cas-fautifs/crush/.
set -euo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echecs=0

for cas in "$RACINE"/tests/cas-fautifs/regle*/; do
  n="$(basename "$cas")"; n="${n#regle}"
  rm -rf "$tmp/specs"; cp -r "$RACINE/specs" "$tmp/specs"; cp "$cas"*.yaml "$tmp/specs/"
  if sortie="$("$RACINE/outils/verifier-specs.sh" "$tmp/specs" 2>&1)"; then
    echo "KO  règle $n : le cas fautif est ACCEPTÉ"; echecs=$((echecs + 1))
  elif grep -q "^KO  règle $n " <<<"$sortie"; then
    echo "OK  règle $n : cas fautif rejeté"
  else
    echo "KO  règle $n : rejet, mais pas par la règle $n"; echecs=$((echecs + 1))
  fi
done

if "$RACINE/outils/tester-crush.sh" "$RACINE/tests/cas-fautifs/crush/crush-attendu.txt" >/dev/null 2>&1; then
  echo "KO  crush : la carte fautive est ACCEPTÉE"; echecs=$((echecs + 1))
else
  echo "OK  crush : carte fautive rejetée"
fi
(( echecs == 0 ))
