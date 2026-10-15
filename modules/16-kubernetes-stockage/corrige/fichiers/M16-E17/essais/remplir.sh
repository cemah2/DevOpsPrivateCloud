#!/usr/bin/env bash
# remplir.sh — remplit les deux volumes de vol-essai-0 (200 fichiers aléatoires de 1 Mio chacun)
# et écrit le manifeste d'empreintes MANIFESTE à la racine de chaque volume (M16-E17).
#   ./remplir.sh            remplir
#   ./remplir.sh verifier   sha256sum -c dans les deux volumes (après restauration)
#   ./remplir.sh modifier   réécrit 10 fichiers du volume RBD (sauvegarde incrémentale)
set -euo pipefail
pod="${POD:-vol-essai-0}"
ns="${NS:-wb-essais}"
ex() { kubectl -n "$ns" exec "$pod" -c essai -- bash -c "$1"; }

case "${1:-remplir}" in
  remplir)
    for d in /rbd /fs; do
      ex "cd $d && for i in \$(seq -w 1 200); do head -c 1048576 /dev/urandom > f\$i.bin; done && sha256sum f*.bin > MANIFESTE && sync"
      echo "$d : $(ex "wc -l < $d/MANIFESTE") fichiers"
    done ;;
  verifier)
    for d in /rbd /fs; do
      echo "== $d"; ex "cd $d && sha256sum -c --quiet MANIFESTE && echo 'tout est OK'"
    done ;;
  modifier)
    ex "cd /rbd && for i in \$(seq -w 1 10); do head -c 1048576 /dev/urandom > f0\$i.bin; done && sha256sum f*.bin > MANIFESTE && sync"
    echo "10 fichiers réécrits dans /rbd (manifeste mis à jour)" ;;
  *) echo "usage : $0 [remplir|verifier|modifier]" >&2; exit 2 ;;
esac
