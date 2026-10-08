#!/usr/bin/env bash
# tester-regles.sh — M08-E14 : test HORS LIGNE d'une carte CRUSH décompilée et modifiée.
# Usage : ./tester-regles.sh carte.txt [règle…]          (défaut : ssd-baie hdd-baie)
# Pour chaque règle : 3 répliques sur 1024 entrées, aucune entrée incomplète (--show-bad-mappings),
# répartition par OSD (--show-utilization), et aucune entrée avec deux OSD de la même baie.
# crushtool : dans « sudo cephadm shell » (dossier monté par --mount), ou paquet ceph-base.
set -euo pipefail
CARTE="${1:?Usage : $0 carte.txt [règle…]}"; shift
REGLES=("$@"); (( ${#REGLES[@]} > 0 )) || REGLES=(ssd-baie hdd-baie)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

crushtool -c "$CARTE" -o "$tmp/carte.bin"     # échoue (avec la ligne) si la carte est mal écrite

# OSD → hôte → baie, lus dans la carte.
declare -A hote_de baie_de
b=""; h=""
while read -r a x _; do
  case "$a" in
    host) h="$x"; b="" ;;
    rack) b="$x"; h="" ;;
    item) [[ -n "$h" && "$x" == osd.* ]] && hote_de[${x#osd.}]="$h"
          [[ -n "$b" ]] && baie_de[$x]="$b" ;;
    "}") h=""; b="" ;;
  esac
done < <(sed 's/#.*//' "$CARTE")

statut=0
for r in "${REGLES[@]}"; do
  id="$(awk -v r="$r" '$1=="rule" && $2==r {f=1} f && $1=="id" {print $2; exit}' "$CARTE")"
  [[ -n "$id" ]] || { echo "== $r : absente de la carte"; statut=1; continue; }
  echo "== $r (id $id)"
  incompletes="$(crushtool -i "$tmp/carte.bin" --test --rule "$id" --num-rep 3 --show-bad-mappings 2>&1 | grep -c 'bad mapping' || true)"
  echo "  entrées incomplètes : $incompletes / 1024"
  doublons=0
  while read -r l; do
    o="${l##*[}"; o="${o%]}"
    vues=" "
    for x in ${o//,/ }; do
      bb="${baie_de[${hote_de[$x]:-?}]:-?}"
      [[ "$vues" == *" $bb "* ]] && { doublons=$((doublons + 1)); break; }
      vues+="$bb "
    done
  done < <(crushtool -i "$tmp/carte.bin" --test --rule "$id" --num-rep 3 --show-mappings 2>/dev/null | grep '^CRUSH rule')
  echo "  entrées avec deux copies dans une même baie : $doublons"
  crushtool -i "$tmp/carte.bin" --test --rule "$id" --num-rep 3 --show-utilization 2>/dev/null | grep -E 'device [0-9]+:' | sed 's/^/  /'
  (( incompletes == 0 && doublons == 0 )) || statut=1
done
exit "$statut"
