#!/usr/bin/env bash
# sonde.sh URL — interroge URL (/sante de MédiAgenda) toutes les 0,5 s pendant une reprise ou un
# canary (M20-E16) ; affiche la version servie (ou X en cas d'échec) et, à Ctrl-C, le bilan.
# Usage : ~/m20/e16/sonde.sh https://mediagenda-recette.apps.par1.medisphere.internal/sante | tee ~/m20/e16/sonde.log
set -u
[[ $# -eq 1 ]] || { echo "usage : $0 URL" >&2; exit 2; }
ok=0
ko=0
declare -A versions=()
bilan() {
  echo
  echo "succès=$ok échecs=$ko"
  for v in "${!versions[@]}"; do echo "  $v : ${versions[$v]}"; done
  exit 0
}
trap bilan INT TERM
while true; do
  if r="$(curl -fsS --max-time 2 "$1" 2>/dev/null)"; then
    ok=$((ok + 1))
    v="$(jq -r '.version // "?"' <<<"$r" 2>/dev/null)"
    versions[$v]=$(( ${versions[$v]:-0} + 1 ))
    printf '%s ' "$v"
  else
    ko=$((ko + 1))
    printf 'X '
  fi
  sleep 0.5
done
