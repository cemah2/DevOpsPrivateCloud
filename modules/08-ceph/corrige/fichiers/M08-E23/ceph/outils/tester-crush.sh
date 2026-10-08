#!/usr/bin/env bash
# outils/tester-crush.sh — test hors ligne de config/crush-attendu.txt (M08-E14, E23) :
# compilation, puis pour chaque règle : aucun « bad mapping » au nombre de répliques attendu,
# et aucune entrée qui place deux copies dans la même baie. Code 0 si tout passe.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CARTE="${1:-$MS_RACINE/config/crush-attendu.txt}"
command -v crushtool >/dev/null || { ms_erreur "crushtool absent (paquet ceph-base)"; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

crushtool -c "$CARTE" -o "$tmp/carte.bin"

# OSD → baie, d'après la carte décompilée (hôte → OSD, baie → hôtes).
declare -A hote_de baie_de
hote=""; baie=""
while read -r a b _; do
  case "$a" in
    host) hote="$b"; baie="" ;;
    rack) baie="$b"; hote="" ;;
    item)
      if [[ -n "$hote" && "$b" == osd.* ]]; then hote_de[${b#osd.}]="$hote"; fi
      if [[ -n "$baie" ]]; then baie_de[$b]="$baie"; fi ;;
    "}") hote=""; baie="" ;;
  esac
done < <(sed 's/#.*//' "$CARTE")

echecs=0
# règle:nombre de répliques (EC 2+1 = 3 morceaux)
for essai in ssd-baie:3 hdd-baie:3 ec-21-hdd:3; do
  regle="${essai%%:*}"; n="${essai##*:}"
  id="$(awk -v r="$regle" '$1=="rule" && $2==r {f=1} f && $1=="id" {print $2; exit}' "$CARTE")"
  [[ -n "$id" ]] || { echo "KO  $regle : absente de la carte"; echecs=$((echecs + 1)); continue; }
  mauvais="$(crushtool -i "$tmp/carte.bin" --test --rule "$id" --num-rep "$n" --show-bad-mappings 2>&1 | grep -c 'bad mapping' || true)"
  doublons=0
  while read -r ligne; do
    osds="${ligne##*[}"; osds="${osds%]}"
    declare -A vues=()
    for o in ${osds//,/ }; do
      b="${baie_de[${hote_de[$o]:-?}]:-?}"
      [[ -n "${vues[$b]:-}" ]] && { doublons=$((doublons + 1)); break; }
      vues[$b]=1
    done
    unset vues
  done < <(crushtool -i "$tmp/carte.bin" --test --rule "$id" --num-rep "$n" --show-mappings 2>/dev/null | grep '^CRUSH rule')
  if (( mauvais == 0 && doublons == 0 )); then
    echo "OK  $regle (id $id) : 1024 entrées, aucune incomplète, aucune baie en double"
  else
    echo "KO  $regle (id $id) : $mauvais entrée(s) incomplète(s), $doublons avec deux copies dans une baie"
    echecs=$((echecs + 1))
  fi
done
(( echecs == 0 ))
