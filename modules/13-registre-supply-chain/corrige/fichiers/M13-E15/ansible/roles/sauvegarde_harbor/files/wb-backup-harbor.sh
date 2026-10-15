#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-backup-harbor.sh — sauvegarde APPLICATIVE de Harbor vers PBS
# M13-E15 (ticket PLAT-1433), RB-131. Déployé par le rôle Ansible sauvegarde_harbor ; lancé chaque
# nuit par wb-backup-harbor.timer.
#
# Ce qui est sauvegardé (une sauvegarde PBS « host/<WB_ID> », espace de noms WB_NS, quatre archives) :
#   base.pxar      vidage de la base « registry » (pg_dump -Fc DANS le conteneur harbor-db, contrôlé
#                  par pg_restore --list) + versions (Harbor, PostgreSQL)
#   config.pxar    harbor.yml (il contient deux secrets : l'archive est chiffrée côté client)
#   secret.pxar    $WB_DATA/secret : clés (keys/secretkey chiffre en base les identifiants des
#                  endpoints ; core/private_key.pem signe les jetons), certificat copié pour le proxy
#   registre.pxar  $WB_DATA/registry : blobs et manifestes
# Ordre : la base D'ABORD, les blobs ENSUITE. Un blob poussé entre les deux est en trop (sans effet) ;
# l'ordre inverse donnerait une base qui référence des blobs absents (« blob unknown »).
# Non sauvegardé : $WB_DATA/database (fichiers PostgreSQL : incohérents à chaud, le vidage les
# remplace), redis (cache Valkey), trivy-adapter (base de Trivy, retéléchargée), job_logs.
#
# Secrets hors du script : /etc/wb-backup/pbs-<hôte>.env et /etc/wb-backup/pbs-<hôte>.key, root 600.
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF=/etc/wb-backup/harbor.conf
log() { printf 'wb-backup-harbor: %s\n' "$*"; }
die() {
  log "ERREUR : $*"
  exit 1
}

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"
: "${WB_HOTE:?}" "${WB_ID:?}" "${WB_NS:?}" "${WB_INSTALL:?}" "${WB_DATA:?}" "${WB_CONTENEUR:?}" "${WB_BASE:?}"
WB_ENV="/etc/wb-backup/pbs-${WB_HOTE}.env"
WB_CLE="/etc/wb-backup/pbs-${WB_HOTE}.key"
WB_TRAVAIL="${WB_TRAVAIL:-/var/lib/wb-backup/harbor}"

for f in "$WB_ENV" "$WB_CLE"; do
  [[ -r "$f" ]] || die "secret PBS illisible : $f"
  [[ "$(stat -c '%U:%a' "$f")" == root:600 ]] || die "$f doit appartenir à root, mode 600"
done
# shellcheck source=/dev/null
source "$WB_ENV"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT

[[ "$(docker inspect -f '{{.State.Running}}' "$WB_CONTENEUR" 2>/dev/null)" == true ]] \
  || die "le conteneur $WB_CONTENEUR ne tourne pas : pas de vidage possible"
[[ -d "$WB_DATA/registry" && -d "$WB_DATA/secret" ]] || die "$WB_DATA/registry ou $WB_DATA/secret absent"

# Pas de sauvegarde pendant un ramasse-miettes : il supprime des blobs que la base vient de lâcher.
# (Table « execution » du gestionnaire de tâches de Harbor 2.x : à vérifier sur ta version.)
gc="$(docker exec "$WB_CONTENEUR" psql -U postgres -d "$WB_BASE" -tAc \
  "SELECT count(*) FROM execution WHERE vendor_type = 'GARBAGE_COLLECTION' AND status = 'Running'" 2>/dev/null || echo 0)"
[[ "${gc:-0}" == 0 ]] || die "un ramasse-miettes est en cours : sauvegarde refusée (relancer après sa fin)"

debut=$(date +%s)
rm -rf "$WB_TRAVAIL"
install -d -o root -g root -m 0700 "$WB_TRAVAIL" "$WB_TRAVAIL/base" "$WB_TRAVAIL/config"
# Nettoyage en sortie, quoi qu'il arrive : le vidage et harbor.yml contiennent des secrets.
trap 'rm -rf "$WB_TRAVAIL"' EXIT

# --- 1. Base -----------------------------------------------------------------------------------------
# pg_dump tourne DANS le conteneur (même version majeure que le serveur) ; le flux est écrit sur l'hôte.
docker exec "$WB_CONTENEUR" pg_dump -U postgres -Fc "$WB_BASE" >"$WB_TRAVAIL/base/$WB_BASE.dump" \
  || die "pg_dump de $WB_BASE en échec"
[[ -s "$WB_TRAVAIL/base/$WB_BASE.dump" ]] || die "vidage vide"
liste="$(docker exec -i "$WB_CONTENEUR" pg_restore --list <"$WB_TRAVAIL/base/$WB_BASE.dump")" \
  || die "vidage illisible par pg_restore"
n="$(grep -c ' TABLE DATA ' <<<"$liste" || true)"
((n > 20)) || die "vidage suspect : $n tables seulement"
{
  printf 'harbor=%s\n' "$(readlink -f "$WB_INSTALL")"
  printf 'postgresql=%s\n' "$(docker exec "$WB_CONTENEUR" psql -U postgres -tAc 'SHOW server_version' 2>/dev/null)"
  printf 'date=%s\n' "$(date -Is)"
} >"$WB_TRAVAIL/base/versions.txt"
log "base : $n tables, $(du -h "$WB_TRAVAIL/base/$WB_BASE.dump" | cut -f1)"

# --- 2. Configuration ----------------------------------------------------------------------------------
cp -a "$WB_INSTALL/harbor.yml" "$WB_TRAVAIL/config/harbor.yml"

# --- 3. Envoi (une seule sauvegarde PBS, archives dans l'ordre : base, configuration, clés, blobs) ------
proxmox-backup-client backup \
  "base.pxar:$WB_TRAVAIL/base" \
  "config.pxar:$WB_TRAVAIL/config" \
  "secret.pxar:$WB_DATA/secret" \
  "registre.pxar:$WB_DATA/registry" \
  --ns "$WB_NS" --backup-type host --backup-id "$WB_ID" --keyfile "$WB_CLE"

log "terminé en $(($(date +%s) - debut)) s"
