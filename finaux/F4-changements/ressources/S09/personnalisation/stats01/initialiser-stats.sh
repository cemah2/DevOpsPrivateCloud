#!/bin/bash
# initialiser-stats.sh — exécuté DANS l'image de stats01 par virt-customize (F4-S09), hors ligne.
set -euo pipefail
# Résolution « provisoire » d'InfoGér (2018) : pas d'enregistrement DNS pour la base.
grep -q 'legacy-rdv01.infoger.local' /etc/hosts || \
  printf '192.168.50.21\tlegacy-rdv01.infoger.local legacy-rdv01\n' >> /etc/hosts
install -d -m 0750 /etc/stats /opt/stats /srv/stats
sed "s/@STATS_MDP@/$(cat /root/infoger/stats.mdp)/" /root/infoger/stats.cnf.modele > /etc/stats/stats.cnf
chmod 0600 /etc/stats/stats.cnf
install -m 0750 /root/infoger/stats-rdv.sh /opt/stats/stats-rdv.sh
install -m 0644 /root/infoger/stats-rdv.cron /etc/cron.d/stats-rdv
# Historique : trois mois de fichiers « produits » (vides de sens, présents pour l'inventaire).
for j in $(seq 1 90); do
  d="$(date -d "-$j days" +%F)"
  printf 'praticien\tmois\trendez_vous\tavec_piece\n' > "/srv/stats/rdv-$d.csv"
  touch -d "$d 02:15" "/srv/stats/rdv-$d.csv"
done
: > /var/log/stats-rdv.log
