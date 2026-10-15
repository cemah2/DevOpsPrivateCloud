#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-backup-conteneurs.sh — sauvegarde des DONNÉES des conteneurs vers PBS
# M12-E29 (ticket PLAT-1355). Même principe que wb-backup-socle.sh (M06-E28) et wb-backup-ceph.sh
# (M08-E25). Déployé par le rôle sauvegarde_conteneurs ; lancé chaque nuit par le timer (01:40).
#
# Configuration non secrète : /etc/wb-backup/conteneurs.conf
#   WB_HOTE, WB_NS                      identifiant et espace de noms PBS (par1/conteneurs)
#   WB_BASES=("conteneur|base|compte")  exports LOGIQUES PostgreSQL (pg_dump -Fc dans le conteneur)
#   WB_VOLUMES=("volume|conteneur")     copies À FROID de volumes nommés : le conteneur indiqué (qui
#                                       écrit dans le volume) est ARRÊTÉ pendant la copie puis relancé ;
#                                       conteneur vide = volume sans écrivain. Liste vide par défaut.
#   WB_IMAGE_OUTIL                      image jetable de la copie de volume (tar), par empreinte
# Secrets (root:root 0600) : /etc/wb-backup/pbs-<hôte>.env (PBS_REPOSITORY, PBS_PASSWORD,
# PBS_FINGERPRINT) et /etc/wb-backup/pbs-<hôte>.key (clé de chiffrement côté client).
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF="${WB_CONF:-/etc/wb-backup/conteneurs.conf}"
log() { printf 'wb-backup-conteneurs: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
WB_BASES=()
WB_VOLUMES=()
# shellcheck source=/dev/null
source "$CONF"
: "${WB_HOTE:?WB_HOTE manquant dans $CONF}"
: "${WB_NS:?WB_NS manquant dans $CONF}"
((${#WB_BASES[@]} + ${#WB_VOLUMES[@]} > 0)) || die "rien à sauvegarder dans $CONF (une sauvegarde vide n'est pas une sauvegarde)"
WB_ENV="${WB_ENV:-/etc/wb-backup/pbs-${WB_HOTE}.env}"
WB_CLE="${WB_CLE:-/etc/wb-backup/pbs-${WB_HOTE}.key}"
WB_TRAVAIL="${WB_TRAVAIL:-/var/lib/wb-backup/travail}"
WB_IMAGE_OUTIL="${WB_IMAGE_OUTIL:-docker.io/library/debian:trixie-slim}"

for f in "$WB_ENV" "$WB_CLE"; do
  [[ -r "$f" ]] || die "secret PBS illisible : $f"
  [[ "$(stat -c '%U:%a' "$f")" == root:600 ]] || die "$f doit appartenir à root, mode 600"
done
# shellcheck source=/dev/null
source "$WB_ENV"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT

debut=$(date +%s)
rm -rf "$WB_TRAVAIL"
install -d -o root -g root -m 0700 "$WB_TRAVAIL" "$WB_TRAVAIL/bases" "$WB_TRAVAIL/volumes"
A_RELANCER=()
nettoyer() {
  local c
  # Un conteneur arrêté pour une copie à froid est relancé QUOI QU'IL ARRIVE.
  for c in "${A_RELANCER[@]}"; do docker start "$c" >/dev/null 2>&1 || log "ATTENTION : $c n'a pas redémarré"; done
  rm -rf "$WB_TRAVAIL"
}
trap nettoyer EXIT

# --- Exports logiques PostgreSQL -------------------------------------------------------------
# pg_dump lit la base dans UNE transaction (instantané cohérent, même pendant les écritures).
# Exécuté DANS le conteneur, sous son utilisateur, par le socket Unix (pas de mot de passe) ; le
# flux sort par la sortie standard : rien n'est écrit dans le conteneur (racine en lecture seule).
sauver_base() {
  local ctr base compte fichier
  IFS='|' read -r ctr base compte <<<"$1"
  [[ -n "$ctr" && -n "$base" && -n "$compte" ]] || die "entrée WB_BASES invalide : « $1 »"
  [[ "$(docker inspect -f '{{.State.Running}}' "$ctr" 2>/dev/null)" == true ]] || die "conteneur $ctr absent ou arrêté"
  fichier="$WB_TRAVAIL/bases/$ctr-$base.dump"
  docker exec "$ctr" pg_dump -U "$compte" -d "$base" -Fc >"$fichier" || die "pg_dump de $base ($ctr) en échec"
  [[ -s "$fichier" ]] || die "export vide : $fichier"
  # Vérification : l'archive se relit (table des matières) avec le pg_restore de la même version.
  docker exec -i "$ctr" pg_restore --list <"$fichier" >"$fichier.toc" || die "archive illisible : $fichier"
  grep -q 'TABLE DATA' "$fichier.toc" || die "archive sans données de table : $fichier"
  docker exec "$ctr" pg_dump --version >"$fichier.version"
  log "base $base ($ctr) : $(stat -c %s "$fichier") octets, $(grep -c 'TABLE DATA' "$fichier.toc") table(s)"
}

# --- Copies de volumes À FROID ---------------------------------------------------------------
sauver_volume() {
  local vol ctr
  IFS='|' read -r vol ctr <<<"$1"
  docker volume inspect "$vol" >/dev/null 2>&1 || die "volume $vol absent"
  if [[ -n "$ctr" ]]; then
    # Un seul volume à la fois : le conteneur à relancer en cas d'échec est mémorisé AVANT l'arrêt.
    A_RELANCER=("$ctr")
    docker stop -t 60 "$ctr" >/dev/null || die "arrêt de $ctr impossible"
  fi
  docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
    -v "$vol:/source:ro" -v "$WB_TRAVAIL/volumes:/dest" "$WB_IMAGE_OUTIL" \
    tar --numeric-owner -C /source -cf "/dest/$vol.tar" . || die "copie du volume $vol en échec"
  if [[ -n "$ctr" ]]; then
    docker start "$ctr" >/dev/null || die "redémarrage de $ctr impossible"
    A_RELANCER=()
  fi
  log "volume $vol : $(stat -c %s "$WB_TRAVAIL/volumes/$vol.tar") octets${ctr:+ (copie à froid, $ctr arrêté puis relancé)}"
}

for b in "${WB_BASES[@]}"; do sauver_base "$b"; done
for v in "${WB_VOLUMES[@]}"; do sauver_volume "$v"; done

archives=()
((${#WB_BASES[@]} == 0)) || archives+=("bases.pxar:$WB_TRAVAIL/bases")
((${#WB_VOLUMES[@]} == 0)) || archives+=("volumes.pxar:$WB_TRAVAIL/volumes")
proxmox-backup-client backup "${archives[@]}" \
  --ns "$WB_NS" --backup-type host --backup-id "$WB_HOTE" --keyfile "$WB_CLE" \
  || die "envoi vers PBS en échec"
log "sauvegarde envoyée vers $WB_NS/host/$WB_HOTE en $(( $(date +%s) - debut )) s"
