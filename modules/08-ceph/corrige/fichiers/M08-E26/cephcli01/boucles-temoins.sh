#!/usr/bin/env bash
# boucles-temoins.sh — charges témoins pendant une mise à jour de Ceph (M08-E26), sur cephcli01.
# Trois boucles d'une opération par seconde, chacune journalise dans /var/tmp/temoins/<boucle>.log :
#   HORODATAGE  ok|ECHEC  durée_en_s  — et « LENT » au-delà de 2 s.
#   rbd    : une ligne écrite et synchronisée (dd oflag=dsync) dans un fichier du RBD monté ;
#   cephfs : idem sur le montage CephFS ;
#   s3     : dépôt puis relecture d'un petit objet par le point d'entrée HTTPS (profil aws de E11/E12).
# Usage : boucles-temoins.sh start|stop|bilan
# Variables : TEMOIN_RBD (défaut /mnt/rbd-test), TEMOIN_CEPHFS (défaut /mnt/cephfs),
#             TEMOIN_S3_PROFIL (défaut medidoc), TEMOIN_S3_COMPARTIMENT (défaut temoins-maj).
set -Eeuo pipefail

D=/var/tmp/temoins
RBD_DIR="${TEMOIN_RBD:-/mnt/rbd-test}"
FS_DIR="${TEMOIN_CEPHFS:-/mnt/cephfs}"
PROFIL="${TEMOIN_S3_PROFIL:-medidoc}"
BUCKET="${TEMOIN_S3_COMPARTIMENT:-temoins-maj}"
ENDPOINT=https://rgw.par1.medisphere.internal

# mesurer NOM COMMANDE… — une itération chronométrée, une ligne de journal.
mesurer() {
  local nom="$1" t0 t1 duree etat=ok
  shift
  t0=$(date +%s.%N)
  # Les opérations sont des fonctions exportées : timeout lance un bash qui les connaît.
  if ! timeout 30 bash -c '"$@"' _ "$@" >/dev/null 2>&1; then etat=ECHEC; fi
  t1=$(date +%s.%N)
  duree=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')
  if [[ "$etat" == ok ]] && awk -v d="$duree" 'BEGIN { exit !(d > 2) }'; then etat="ok LENT"; fi
  printf '%s %s %s\n' "$(date -Is)" "$etat" "$duree" >> "$D/$nom.log"
}

ecrire_ligne() { date -Is | dd of="$1/temoin-maj.txt" oflag=dsync,append conv=notrunc status=none; }
s3_aller_retour() {
  local f
  f="$(mktemp)"
  date -Is > "$f"
  aws --profile "$PROFIL" --endpoint-url "$ENDPOINT" s3 cp "$f" "s3://$BUCKET/temoin.txt" --only-show-errors \
    && aws --profile "$PROFIL" --endpoint-url "$ENDPOINT" s3 cp "s3://$BUCKET/temoin.txt" - --only-show-errors | cmp -s - "$f"
  local r=$?
  rm -f "$f"
  return "$r"
}

boucle() {
  local nom="$1"
  shift
  while [[ -e "$D/actif" ]]; do
    mesurer "$nom" "$@"
    sleep 1
  done
}

case "${1:-}" in
  start)
    mkdir -p "$D"
    touch "$D/actif"
    export -f mesurer ecrire_ligne s3_aller_retour boucle
    export D PROFIL BUCKET ENDPOINT
    nohup bash -c "boucle rbd ecrire_ligne '$RBD_DIR'" >/dev/null 2>&1 &
    nohup bash -c "boucle cephfs ecrire_ligne '$FS_DIR'" >/dev/null 2>&1 &
    nohup bash -c "boucle s3 s3_aller_retour" >/dev/null 2>&1 &
    echo "boucles lancées, journaux dans $D"
    ;;
  stop)
    rm -f "$D/actif"
    echo "les boucles s'arrêtent à la fin de leur itération"
    ;;
  bilan)
    for f in "$D"/*.log; do
      [[ -e "$f" ]] || continue
      awk -v n="$(basename "$f" .log)" '
        { total++; if ($2 == "ECHEC") echec++; if ($NF + 0 > max) { max = $NF + 0; quand = $1 }; if ($0 ~ /LENT/) lent++ }
        END { printf "%-7s %6d opérations, %d échec(s), %d lente(s), max %.3f s à %s\n", n, total, echec, lent, max, quand }' "$f"
    done
    ;;
  *)
    echo "Usage : $0 start|stop|bilan" >&2
    exit 2
    ;;
esac
