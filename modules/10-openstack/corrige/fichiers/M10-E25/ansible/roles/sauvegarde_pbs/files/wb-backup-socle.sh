#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-backup-socle.sh — sauvegarde APPLICATIVE d'un service socle vers PBS
# M06-E28 (ticket PLAT-754), étendu en M09-E29 (PLAT-1055) : élément « pve », et en M10-E25
# (PLAT-1151) : élément « openstack ».
# Généralise wb-backup-gitlab.sh (M01-E28) aux services du socle, aux nœuds Proxmox VE et au plan
# de contrôle OpenStack.
# Déployé par le rôle Ansible sauvegarde_pbs ; lancé chaque nuit par wb-backup-socle.timer.
#
# Éléments (WB_ELEMENTS, dans /etc/wb-backup/socle.conf) :
#   powerdns  base SQLite copiée EN LIGNE par l'API de sauvegarde de SQLite (.backup), vérifiée,
#             + /etc/powerdns
#   kea       baux exportés par la commande lease4-get-all (socket de contrôle local, lease_cmds)
#             + fichiers CSV bruts + /etc/kea
#   netbox    pg_dump (format custom) + fichiers téléversés (media) + configuration (secrets)
#   stepca    /etc/step-ca copié en arborescence (configuration, base Badger, certificats, clé CHIFFRÉE de
#             l'intermédiaire), step-ca ARRÊTÉ le temps de la copie (base non partageable) ; SANS la clé racine
#             (refus si elle est présente) ni le fichier de mot de passe de l'intermédiaire (Vault)
#   pve       nœud Proxmox VE : base de pmxcfs (/var/lib/pve-cluster/config.db) copiée EN LIGNE par
#             l'API de sauvegarde de SQLite et vérifiée, arborescence /etc/pve (fichiers d'invités,
#             stockage, HA, pare-feu, secrets de priv/ : l'archive est chiffrée), fichiers propres
#             au nœud (WB_PVE_FICHIERS : Corosync, réseau, FRR…), versions des paquets
#   openstack dernière sauvegarde COMPLÈTE Mariabackup de Kolla (volume Docker mariadb_backup, prise
#             depuis adm01 par « kolla-ansible mariadb-backup »), refusée si elle a plus de
#             WB_OS_AGE_MAX secondes ou si l'archive est corrompue ; image MariaDB et empreintes
#             des images en service (une restauration se fait avec la MÊME image) ; clés Fernet
#             de Keystone (facultatif) ; APRÈS un envoi réussi, purge locale des sauvegardes de
#             plus de WB_OS_RETENTION_JOURS jours (Kolla ne purge rien)
#
# Secrets hors du script : /etc/wb-backup/pbs-<hôte>.env (PBS_REPOSITORY, PBS_PASSWORD,
# PBS_FINGERPRINT) et /etc/wb-backup/pbs-<hôte>.key, root:root 0600.
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF=/etc/wb-backup/socle.conf

log() { printf 'wb-backup-socle: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"

: "${WB_HOTE:?WB_HOTE manquant dans $CONF}"
: "${WB_NS:?WB_NS manquant dans $CONF}"
: "${WB_ELEMENTS:?WB_ELEMENTS manquant dans $CONF}"
WB_ENV="${WB_ENV:-/etc/wb-backup/pbs-${WB_HOTE}.env}"
WB_CLE="${WB_CLE:-/etc/wb-backup/pbs-${WB_HOTE}.key}"
WB_TRAVAIL="${WB_TRAVAIL:-/var/lib/wb-backup/travail}"

for f in "$WB_ENV" "$WB_CLE"; do
  [[ -r "$f" ]] || die "secret PBS illisible : $f"
  [[ "$(stat -c '%U:%a' "$f")" == root:600 ]] || die "$f doit appartenir à root, mode 600"
done
# shellcheck source=/dev/null
source "$WB_ENV"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT

debut=$(date +%s)
rm -rf "$WB_TRAVAIL"
install -d -o root -g root -m 0700 "$WB_TRAVAIL"
# Nettoyage en sortie, quoi qu'il arrive : les copies de travail contiennent des secrets.
trap 'rm -rf "$WB_TRAVAIL"' EXIT

# --- Éléments ----------------------------------------------------------------------------------

sauver_powerdns() {
  local base="${WB_PDNS_BASE:-/var/lib/powerdns/pdns.sqlite3}" d="$WB_TRAVAIL/powerdns" copie
  command -v sqlite3 >/dev/null || die "sqlite3 absent"
  install -d -m 0700 "$d"
  # .backup : copie cohérente même pendant les écritures (API ou DNS UPDATE de Kea).
  # Sous le compte pdns, propriétaire de la base : lancé en root, sqlite3 pourrait créer des
  # fichiers -wal/-shm appartenant à root, que PowerDNS ne pourrait plus écrire (M06-E06).
  # La copie est écrite à côté de la base (dossier de pdns), puis déplacée dans le dossier de travail.
  copie="$(dirname "$base")/.wb-backup-$$.sqlite3"
  if ! runuser -u pdns -- sqlite3 "$base" ".backup '$copie'"; then
    rm -f "$copie"; die "copie de la base PowerDNS impossible"
  fi
  mv "$copie" "$d/pdns.sqlite3"
  [[ "$(sqlite3 "$d/pdns.sqlite3" 'PRAGMA integrity_check;')" == ok ]] || die "copie de la base PowerDNS incohérente"
  sqlite3 "$d/pdns.sqlite3" 'SELECT name, type FROM domains ORDER BY name;' > "$d/zones.txt"
  [[ -s "$d/zones.txt" ]] || die "aucune zone dans la copie de la base PowerDNS"
  tar -C / -cf "$d/etc-powerdns.tar" etc/powerdns
  pdns_server --version > "$d/version.txt" 2>&1 || true
  log "powerdns : $(wc -l < "$d/zones.txt") zone(s)"
}

sauver_kea() {
  local sock="${WB_KEA_SOCKET:-/run/kea/kea4-ctrl-socket}" d="$WB_TRAVAIL/kea" reponse code
  command -v socat >/dev/null || die "socat absent"
  install -d -m 0700 "$d"
  # Export cohérent par Kea lui-même (le fichier CSV, lui, est réécrit par le processus LFC).
  reponse="$(printf '%s' '{"command": "lease4-get-all"}' | socat -t 10 - "UNIX-CONNECT:$sock")"
  code="$(jq -r '.result' <<<"$reponse")"
  # 0 = baux renvoyés, 3 = aucun bail (« empty ») : les deux sont normaux.
  [[ "$code" == 0 || "$code" == 3 ]] || die "lease4-get-all a échoué (résultat $code)"
  printf '%s\n' "$reponse" > "$d/baux-lease4-get-all.json"
  install -d -m 0700 "$d/var-lib-kea"
  cp -a /var/lib/kea/. "$d/var-lib-kea/"
  tar -C / -cf "$d/etc-kea.tar" etc/kea
  kea-dhcp4 -V > "$d/version.txt" 2>&1 || true
  log "kea : $(jq '.arguments.leases | length // 0' "$d/baux-lease4-get-all.json") bail(s)"
}

sauver_netbox() {
  local racine="${WB_NETBOX_DOSSIER:-/opt/netbox}" base="${WB_NETBOX_BASE:-netbox}" d="$WB_TRAVAIL/netbox" f
  local config=(netbox/netbox/configuration.py)
  install -d -m 0700 "$d"
  # pg_dump : instantané transactionnel cohérent, sans arrêter NetBox.
  runuser -u postgres -- pg_dump -Fc -d "$base" > "$d/netbox.pgdump"
  pg_restore --list "$d/netbox.pgdump" > /dev/null || die "export PostgreSQL illisible"
  tar -C "$racine/netbox" -cf "$d/media.tar" media
  # configuration.py contient SECRET_KEY et API_TOKEN_PEPPERS : indispensables pour relire les
  # sessions et les jetons v2 restaurés (doublon volontaire de Vault, archive chiffrée).
  for f in local_requirements.txt gunicorn.py; do [[ -f "$racine/$f" ]] && config+=("$f"); done
  tar -C "$racine" -cf "$d/config.tar" "${config[@]}"
  cp -a "$racine/netbox/release.yaml" "$d/" 2>/dev/null || true
  log "netbox : export de $(du -h "$d/netbox.pgdump" | cut -f1)"
}

sauver_stepca() {
  local dossier="${WB_STEPCA_DOSSIER:-/etc/step-ca}" d="$WB_TRAVAIL/stepca" t0 exclus=()
  install -d -m 0700 "$d"
  # Garde-fou de la politique (M06-E02, M06-E33) : la clé racine n'a rien à faire sur ca01.
  if find "$dossier" -iname '*root*key*' -print -quit | grep -q .; then
    die "une clé racine est présente sous $dossier : sauvegarde refusée (incident à ouvrir)"
  fi
  for e in ${WB_STEPCA_EXCLURE:-}; do exclus+=("--exclude=${dossier#/}/$e"); done
  t0=$(date +%s)
  systemctl stop step-ca.service
  # Redémarrage garanti même si la copie échoue.
  trap 'systemctl start step-ca.service; rm -rf "$WB_TRAVAIL"' EXIT
  # Copie en ARBORESCENCE (pas une archive tar) : le catalogue de PBS liste alors chaque fichier,
  # ce qui permet de PROUVER l'absence de clé racine sans restaurer (M06-E28).
  tar -C / "${exclus[@]}" -cf - "${dossier#/}" | tar -C "$d" -xpf -
  systemctl start step-ca.service
  trap 'rm -rf "$WB_TRAVAIL"' EXIT
  step-ca version > "$d/version.txt" 2>&1 || true
  log "stepca : service suspendu $(( $(date +%s) - t0 )) s"
}

sauver_pve() {
  local d="$WB_TRAVAIL/pve" base=/var/lib/pve-cluster/config.db f
  command -v sqlite3 >/dev/null || die "sqlite3 absent"
  [[ -r "$base" ]] || die "base de pmxcfs introuvable : $base (est-ce un nœud Proxmox VE ?)"
  install -d -m 0700 "$d"
  # .backup : copie cohérente pendant que pmxcfs écrit (même mécanisme que pour PowerDNS).
  sqlite3 "$base" ".backup '$d/config.db'" || die "copie de config.db impossible"
  [[ "$(sqlite3 "$d/config.db" 'PRAGMA integrity_check;')" == ok ]] || die "copie de config.db incohérente"
  # Témoin lisible sans restaurer : nombre d'entrées et fichiers de VM présents dans la base.
  sqlite3 "$d/config.db" "SELECT name FROM tree WHERE name LIKE '%.conf' ORDER BY name;" > "$d/config-db-fichiers.txt" \
    || die "lecture de la table tree de config.db impossible"
  # Arborescence /etc/pve (vue FUSE de la même base) : restauration d'un fichier isolé sans
  # toucher à la base (cas « fichier de VM supprimé par erreur »).
  install -d -m 0700 "$d/etc-pve"
  cp -a /etc/pve/. "$d/etc-pve/" || die "copie de /etc/pve impossible (pmxcfs arrêté ?)"
  [[ -s "$d/etc-pve/corosync.conf" ]] || die "/etc/pve/corosync.conf absent de la copie : nœud hors cluster ?"
  for f in ${WB_PVE_FICHIERS:-}; do
    [[ -e "$f" ]] || { log "pve : $f absent, ignoré"; continue; }
    tar -C / -rf "$d/fichiers-noeud.tar" "${f#/}"
  done
  pveversion -v > "$d/pveversion.txt" 2>&1 || true
  log "pve : config.db ($(wc -l < "$d/config-db-fichiers.txt") fichier(s) .conf), /etc/pve, fichiers du nœud"
}

sauver_openstack() {
  local vol="${WB_OS_VOLUME:-mariadb_backup}" d="$WB_TRAVAIL/openstack" racine dernier fichier age fernet
  command -v docker >/dev/null || die "docker absent"
  racine="$(docker volume inspect -f '{{.Mountpoint}}' "$vol" 2>/dev/null)" || die "volume Docker $vol introuvable"
  # Le script backup.sh de l'image Kolla mariadb-server écrit le chemin de la dernière complète,
  # VU DU CONTENEUR (/backup//full-<date>/mysqlbackup-<date>.qp.xbc.xbs.gz), dans last_full_file.
  [[ -r "$racine/last_full_file" ]] || die "aucune sauvegarde complète Mariabackup (last_full_file absent)"
  dernier="$(<"$racine/last_full_file")"
  fichier="$racine/${dernier#/backup/}"
  [[ -s "$fichier" ]] || die "fichier de sauvegarde introuvable ou vide : $fichier"
  age=$(( $(date +%s) - $(stat -c %Y "$fichier") ))
  (( age <= ${WB_OS_AGE_MAX:-93600} )) || die "dernière sauvegarde complète trop ancienne ($(( age / 3600 )) h) : la sauvegarde de adm01 a-t-elle tourné ?"
  gzip -t "$fichier" || die "archive Mariabackup corrompue : $fichier"
  install -d -m 0700 "$d"
  cp -a "$fichier" "$d/"
  printf '%s\n' "$dernier" > "$d/last_full_file"
  # Une restauration se fait avec la MÊME image MariaDB (format des fichiers, version de mariabackup).
  docker inspect -f '{{.Config.Image}} {{.Image}}' mariadb > "$d/image-mariadb.txt" \
    || die "conteneur mariadb introuvable"
  docker ps --format '{{.Names}}' | sort | while read -r c; do
    docker inspect -f '{{.Name}} {{.Config.Image}} {{.Image}}' "$c"
  done > "$d/images-en-service.txt"
  # Clés Fernet : utiles pour éviter une réauthentification générale après une reconstruction
  # rapide ; sans valeur après fernet_key_rotation_interval (3 jours par défaut).
  if [[ "${WB_OS_FERNET:-oui}" == oui ]]; then
    fernet="$(docker volume inspect -f '{{.Mountpoint}}' keystone_fernet_tokens 2>/dev/null)" \
      || die "volume keystone_fernet_tokens introuvable"
    tar -C "$fernet" -cf "$d/fernet-keys.tar" .
  fi
  log "openstack : $(basename "$fichier") ($(du -h "$fichier" | cut -f1), $(( age / 60 )) min)"
}

# Purge APRÈS un envoi réussi seulement. Ne touche que full-* et incr-* du volume, jamais la
# complète désignée par last_full_file (elle a moins de WB_OS_AGE_MAX : jamais concernée).
apres_openstack() {
  local racine jours="${WB_OS_RETENTION_JOURS:-7}" n
  racine="$(docker volume inspect -f '{{.Mountpoint}}' "${WB_OS_VOLUME:-mariadb_backup}")"
  n="$(find "$racine" -mindepth 1 -maxdepth 1 -type d \( -name 'full-*' -o -name 'incr-*' \) -mtime "+$jours" | wc -l)"
  find "$racine" -mindepth 1 -maxdepth 1 -type d \( -name 'full-*' -o -name 'incr-*' \) -mtime "+$jours" \
    -exec rm -rf -- {} +
  log "openstack : $n sauvegarde(s) locale(s) de plus de $jours jours purgée(s)"
}

for e in $WB_ELEMENTS; do
  case "$e" in
    powerdns | kea | netbox | stepca | pve | openstack) log "élément $e" && "sauver_$e" ;;
    *) die "élément inconnu : $e" ;;
  esac
done

sommes="$(cd "$WB_TRAVAIL" && find . -type f -print0 | sort -z | xargs -0 sha256sum)"
printf '%s\n' "$sommes" > "$WB_TRAVAIL/SHA256SUMS"

log "envoi vers PBS ($PBS_REPOSITORY, espace de noms $WB_NS)"
proxmox-backup-client backup "socle.pxar:$WB_TRAVAIL" \
  --ns "$WB_NS" --backup-type host --backup-id "$WB_HOTE" --keyfile "$WB_CLE"

# Actions d'après envoi (purges locales), seulement si l'envoi a réussi (set -e).
for e in $WB_ELEMENTS; do
  if [[ "$(type -t "apres_$e")" == function ]]; then "apres_$e"; fi
done

log "terminé en $(( $(date +%s) - debut )) s ($WB_ELEMENTS)"
