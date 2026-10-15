#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-restaurer-harbor.sh — restauration de Harbor depuis PBS (M13-E15, RB-131)
# Déployé par le rôle sauvegarde_harbor ; JAMAIS lancé par Ansible ni par une minuterie.
#
# Usage : wb-restaurer-harbor.sh [--instantane host/<id>/<date>] --je-sais-ce-que-je-fais
#   Sans --instantane : la dernière sauvegarde de WB_ID dans WB_NS (/etc/wb-backup/harbor.conf).
#
# Préconditions (vérifiées) : Harbor installé par le rôle harbor dans la MÊME version que la source
# (versions.txt de l'archive « base »). Écrase $WB_DATA/registry, $WB_DATA/secret (gardés en
# *.avant-restauration) et la base « registry ».
# Étapes : arrêt de Harbor → blobs et clés → base seule démarrée, base recréée, vidage restauré →
# politiques de réplication DÉSACTIVÉES dans la base (avant tout démarrage complet) → démarrage.
# =============================================================================
set -Eeuo pipefail
umask 077
CONF=/etc/wb-backup/harbor.conf
log() { printf 'wb-restaurer-harbor: %s\n' "$*"; }
die() {
  log "ERREUR : $*"
  exit 1
}

instantane=""
confirme=0
while (($#)); do
  case "$1" in
    --instantane)
      instantane="${2:-}"
      shift 2
      ;;
    --je-sais-ce-que-je-fais)
      confirme=1
      shift
      ;;
    *) die "option inconnue : $1" ;;
  esac
done
((confirme)) || die "restauration destructive : relance avec --je-sais-ce-que-je-fais (RB-131)"
[[ $EUID -eq 0 ]] || die "à lancer en root"
# shellcheck source=/dev/null
source "$CONF"
: "${WB_HOTE:?}" "${WB_ID:?}" "${WB_NS:?}" "${WB_INSTALL:?}" "${WB_DATA:?}" "${WB_BASE:?}"
# shellcheck source=/dev/null
source "/etc/wb-backup/pbs-${WB_HOTE}.env"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT
CLE="/etc/wb-backup/pbs-${WB_HOTE}.key"
T=/var/lib/wb-backup/restauration
debut=$(date +%s)

if [[ -z "$instantane" ]]; then
  instantane="$(proxmox-backup-client snapshot list --ns "$WB_NS" --output-format json |
    jq -r --arg id "$WB_ID" '[.[] | select(."backup-id" == $id)] | max_by(."backup-time")
      | "\(."backup-type")/\(."backup-id")/\(."backup-time" | todate)"')"
fi
[[ "$instantane" == host/* ]] || die "aucune sauvegarde trouvée pour $WB_ID dans $WB_NS"
log "sauvegarde utilisée : $instantane"

rm -rf "$T"
install -d -m 0700 "$T"
trap 'rm -rf "$T"' EXIT
proxmox-backup-client restore --ns "$WB_NS" "$instantane" base.pxar "$T/base" --keyfile "$CLE"
v_source="$(sed -n 's|^harbor=.*/\([0-9][0-9.]*\)/harbor$|\1|p' "$T/base/versions.txt")"
v_ici="$(readlink -f "$WB_INSTALL" | sed -n 's|.*/\([0-9][0-9.]*\)/harbor$|\1|p')"
[[ -n "$v_source" && "$v_source" == "$v_ici" ]] \
  || die "versions différentes (source ${v_source:-?}, ici ${v_ici:-?}) : installe la même version (rôle harbor)"

log "arrêt de Harbor"
systemctl stop harbor.service
log "restauration des blobs et des clés (écrase $WB_DATA/registry et $WB_DATA/secret)"
for a in registre:registry secret:secret; do
  d="$WB_DATA/${a#*:}"
  rm -rf "${d:?}.avant-restauration"
  if [[ -e "$d" ]]; then mv "$d" "$d.avant-restauration"; fi
  proxmox-backup-client restore --ns "$WB_NS" "$instantane" "${a%%:*}.pxar" "$d" --keyfile "$CLE"
done

log "base seule (service « postgresql » du docker-compose.yml, conteneur harbor-db)"
cd "$WB_INSTALL"
docker compose up -d postgresql
for _ in $(seq 1 30); do
  if docker exec harbor-db pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec harbor-db psql -U postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS ${WB_BASE};" -c "CREATE DATABASE ${WB_BASE};"
docker exec -i harbor-db pg_restore -U postgres --no-owner --role=postgres -d "$WB_BASE" --exit-on-error \
  <"$T/base/${WB_BASE}.dump"
# Les politiques de réplication restaurées viennent de la source : désactivées AVANT le démarrage
# complet (sinon une politique planifiée partirait, vers la source ou vers soi-même).
docker exec harbor-db psql -U postgres -d "$WB_BASE" -v ON_ERROR_STOP=1 \
  -c "UPDATE replication_policy SET enabled = false;"
docker compose stop postgresql

log "démarrage de Harbor"
systemctl start harbor.service
log "terminé en $(($(date +%s) - debut)) s ; anciens dossiers : $WB_DATA/*.avant-restauration (à supprimer après vérification)"
