#!/bin/sh
# outils/tester-routes.sh — rejoue alertmanager/routes-tests.txt contre une configuration (M21-E07).
# Usage : outils/tester-routes.sh am.yml alertmanager/routes-tests.txt
set -eu
config=$1 essais=$2
erreurs=0
while IFS='|' read -r attendu etiquettes; do
  attendu=$(echo "$attendu" | tr -d ' ')
  case "$attendu" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2086  # découpage voulu : une étiquette par argument
  obtenu=$(amtool config routes test --config.file="$config" $etiquettes)
  if [ "$obtenu" = "$attendu" ]; then
    echo "OK  $etiquettes -> $obtenu"
  else
    echo "KO  $etiquettes -> $obtenu (attendu : $attendu)" >&2
    erreurs=$((erreurs + 1))
  fi
done < "$essais"
[ "$erreurs" -eq 0 ]
