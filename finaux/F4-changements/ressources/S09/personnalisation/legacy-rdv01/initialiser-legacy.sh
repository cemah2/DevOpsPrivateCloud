#!/bin/bash
# initialiser-legacy.sh — exécuté DANS l'image de legacy-rdv01 par virt-customize (F4-S09), hors ligne :
# pas de systemd, pas de réseau entrant. Installe Legacy-RDV comme InfoGér l'avait fait, démarre un
# MariaDB TEMPORAIRE (sans réseau, socket local), charge le schéma et les données, puis l'arrête.
# Entrées (copiées par virt-customize dans /root/infoger) :
#   app/            code de apps/legacy-rdv (dépôt du workbook), config.php d'origine compris
#   donnees/        donnees.sql, pieces/, pieces-dates.txt (generer-donnees.pl)
#   stats.mdp       mot de passe du compte MariaDB « stats » (le même est écrit dans stats01)
set -euo pipefail
S=/root/infoger
APP=/var/www/legacy-rdv

# --- Code et répertoires (procédure d'installation d'InfoGér, apps/legacy-rdv/README.md) ----------
install -d -m 0755 "$APP" /var/log/legacy-rdv
cp -a "$S/app/." "$APP/"
chown -R root:root "$APP"
chown -R www-data:www-data "$APP/uploads" /var/log/legacy-rdv
cp "$APP/vm/apache-legacy-rdv.conf" /etc/apache2/sites-available/legacy-rdv.conf
a2dissite 000-default >/dev/null
a2ensite legacy-rdv >/dev/null
cp "$APP/vm/cron.d-legacy-rdv" /etc/cron.d/legacy-rdv
chmod 0644 /etc/cron.d/legacy-rdv

# --- MariaDB temporaire -------------------------------------------------------------------------
if [ ! -d /var/lib/mysql/mysql ]; then
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
fi
install -d -o mysql -g mysql -m 0755 /run/mysqld
mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking \
  --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid >/var/tmp/mariadbd-init.log 2>&1 &
for _ in $(seq 1 60); do
  mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1 && break
  sleep 1
done
mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null

STATS_MDP="$(cat "$S/stats.mdp")"
mariadb --socket=/run/mysqld/mysqld.sock <<SQL
CREATE DATABASE IF NOT EXISTS legacy_rdv CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'legacy_rdv'@'localhost' IDENTIFIED BY 'InfoGer2014!';
GRANT SELECT, INSERT, UPDATE, DELETE ON legacy_rdv.* TO 'legacy_rdv'@'localhost';
CREATE USER IF NOT EXISTS 'stats'@'192.168.50.40' IDENTIFIED BY '${STATS_MDP}';
GRANT SELECT ON legacy_rdv.rendez_vous TO 'stats'@'192.168.50.40';
FLUSH PRIVILEGES;
SQL
mariadb --socket=/run/mysqld/mysqld.sock legacy_rdv < "$APP/schema.sql"
mariadb --socket=/run/mysqld/mysqld.sock legacy_rdv < "$S/donnees/donnees.sql"

# Vidage local « de la nuit dernière » (copie de données à effacer au décommissionnement, F4-S14).
install -d -m 0700 /var/backups/infoger
mariadb-dump --socket=/run/mysqld/mysqld.sock --single-transaction legacy_rdv \
  | gzip -9 > "/var/backups/infoger/legacy_rdv-$(date -d yesterday +%F).sql.gz"

mariadb-admin --socket=/run/mysqld/mysqld.sock shutdown
for _ in $(seq 1 60); do
  [ -e /run/mysqld/mysqld.pid ] || break
  sleep 1
done
rm -rf /run/mysqld

# --- Pièces jointes, avec leurs dates (la purge nocturne travaille sur la date du fichier) --------
cp -a "$S/donnees/pieces/." "$APP/uploads/"
while IFS="$(printf '\t')" read -r f d; do
  touch -d "$d" "$APP/uploads/$f"
done < "$S/donnees/pieces-dates.txt"
chown www-data:www-data "$APP"/uploads/*.pdf
chmod 0640 "$APP"/uploads/*.pdf

# --- Journal applicatif « vécu » ------------------------------------------------------------------
{
  echo "[$(date -d '-3 days' '+%Y-%m-%d 03:30:01')] INFO cron purge : 0 fichier(s) supprimé(s)"
  echo "[$(date -d '-2 days' '+%Y-%m-%d 09:12:44')] ERREUR 192.168.50.112 pièce jointe introuvable pour le rendez-vous 412"
  echo "[$(date -d '-1 days' '+%Y-%m-%d 11:02:09')] ALERTE 192.168.50.117 jeton CSRF invalide ou session absente"
} > /var/log/legacy-rdv/app.log
chown www-data:adm /var/log/legacy-rdv/app.log
chmod 0640 /var/log/legacy-rdv/app.log
