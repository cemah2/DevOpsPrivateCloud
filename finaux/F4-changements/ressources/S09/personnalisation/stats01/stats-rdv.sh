#!/bin/bash
# /opt/stats/stats-rdv.sh — statistiques nocturnes de Legacy-RDV (InfoGér, 2018).
# Lit la base de legacy-rdv01 (compte « stats », SELECT sur rendez_vous) et écrit un CSV par jour
# dans /srv/stats ; la direction le récupère « par le partage » (le partage n'existe plus depuis 2020).
set -euo pipefail
SORTIE=/srv/stats
JOURNAL=/var/log/stats-rdv.log
mkdir -p "$SORTIE"
f="$SORTIE/rdv-$(date +%F).csv"
if mariadb --defaults-extra-file=/etc/stats/stats.cnf --batch --connect-timeout=10 -e "
    SELECT praticien, DATE_FORMAT(date_rdv, '%Y-%m') AS mois, COUNT(*) AS rendez_vous,
           SUM(piece_jointe IS NOT NULL) AS avec_piece
    FROM rendez_vous
    WHERE date_rdv >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY praticien, mois ORDER BY mois, praticien;" > "$f.tmp" 2>>"$JOURNAL"; then
  mv "$f.tmp" "$f"
  echo "$(date -Is) OK $(($(wc -l < "$f") - 1)) lignes -> $f" >> "$JOURNAL"
else
  rm -f "$f.tmp"
  echo "$(date -Is) ERREUR lecture de la base de legacy-rdv01 impossible" >> "$JOURNAL"
  exit 1
fi
