#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-backup-ceph.sh — sauvegarde hors cluster de ceph-par1 vers PBS (M08-E25, PLAT-951)
# Déployé sur cephcli01 par le rôle Ansible sauvegarde_ceph ; lancé chaque nuit par wb-backup-ceph.timer.
#
# 1. Volumes RBD : images listées (WB_IMAGES) + images des pools de découverte (WB_POOLS_DECOUVERTE,
#    tous espaces de noms) qui portent la métadonnée WB_META_CLE = « oui » (désignation par l'équipe,
#    M08-E31). Pour chacune : instantané « sauv-AAAAMMJJ », puis export INCRÉMENTAL depuis l'instantané
#    de sauvegarde précédent, ou COMPLET le jour WB_JOUR_COMPLET ou si la base manque.
# 2. Configuration du cluster : archive produite sur ceph01 par la commande forcée de wb-sauvegarde.
# 3. Envoi vers PBS, chiffré côté client : deux sauvegardes (backup-id) dans l'espace par1/ceph.
# 4. Seulement après un envoi réussi : suppression des instantanés de sauvegarde antérieurs (le dernier
#    reste, c'est la base de l'incrémental de demain).
#
# Secrets hors du script (root:root 0600) : /etc/wb-backup/pbs-cephcli01.env (PBS_REPOSITORY,
# PBS_PASSWORD, PBS_FINGERPRINT), /etc/wb-backup/pbs-cephcli01.key, /etc/wb-backup/ssh-export-config,
# /etc/ceph/ceph.client.sauvegarde.keyring.
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# Test : WB_DATE=AAAAMMJJ force la date du jour (simulation d'une chaîne sur plusieurs jours).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF=/etc/wb-backup/ceph.conf

log() { printf 'wb-backup-ceph: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"

: "${WB_HOTE:?WB_HOTE manquant dans $CONF}"
: "${WB_NS:?WB_NS manquant dans $CONF}"
: "${WB_ID_CEPH:?WB_ID_CEPH manquant dans $CONF}"
: "${WB_EXPORT_HOTE:?WB_EXPORT_HOTE manquant dans $CONF}"
WB_ENV="${WB_ENV:-/etc/wb-backup/pbs-${WB_HOTE}.env}"
WB_CLE="${WB_CLE:-/etc/wb-backup/pbs-${WB_HOTE}.key}"
WB_CLE_SSH="${WB_CLE_SSH:-/etc/wb-backup/ssh-export-config}"
WB_TRAVAIL="${WB_TRAVAIL:-/var/lib/wb-backup/travail}"
WB_META_CLE="${WB_META_CLE:-medisphere.sauvegarde}"
WB_JOUR_COMPLET="${WB_JOUR_COMPLET:-7}"
WB_ID_RBD="${WB_ID_RBD:-ceph-par1-rbd}"
WB_ID_CONFIG="${WB_ID_CONFIG:-ceph-par1-config}"
[[ -n "${WB_IMAGES+x}" ]] || WB_IMAGES=()
[[ -n "${WB_POOLS_DECOUVERTE+x}" ]] || WB_POOLS_DECOUVERTE=()

for f in "$WB_ENV" "$WB_CLE" "$WB_CLE_SSH"; do
  [[ -r "$f" ]] || die "secret illisible : $f"
  [[ "$(stat -c '%U:%a' "$f")" == root:600 ]] || die "$f doit appartenir à root, mode 600"
done
# shellcheck source=/dev/null
source "$WB_ENV"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT

jour="${WB_DATE:-$(date +%Y%m%d)}"
[[ "$jour" =~ ^[0-9]{8}$ ]] || die "date invalide : $jour"
instantane="sauv-$jour"
jour_semaine="$(date -d "$jour" +%u)"
debut=$(date +%s)

rm -rf "$WB_TRAVAIL"
install -d -o root -g root -m 0700 "$WB_TRAVAIL" "$WB_TRAVAIL/rbd" "$WB_TRAVAIL/config"
# Nettoyage en sortie, quoi qu'il arrive : les exports contiennent des données en clair.
trap 'rm -rf "$WB_TRAVAIL"' EXIT

rbdc() { rbd --id "$WB_ID_CEPH" "$@"; }

# --- 1. Liste des images ----------------------------------------------------------------------------
images=("${WB_IMAGES[@]}")
for pool in "${WB_POOLS_DECOUVERTE[@]}"; do
  espaces="$(rbdc namespace ls "$pool" --format json | jq -r '.[].name')" || die "espaces de noms illisibles : $pool"
  for ns in "" $espaces; do
    spec_pool="$pool${ns:+/$ns}"
    for img in $(rbdc ls "$spec_pool"); do
      if [[ "$(rbdc image-meta get "$spec_pool/$img" "$WB_META_CLE" 2>/dev/null || true)" == oui ]]; then
        images+=("$spec_pool/$img")
      fi
    done
  done
done
((${#images[@]} > 0)) || die "aucune image à sauvegarder : rien vu n'est pas « tout va bien »"
log "${#images[@]} image(s) : ${images[*]}"

# --- 2. Instantanés et exports ------------------------------------------------------------------------
printf 'image\ttype\tdepuis\tjusqua\toctets\tsha256\n' > "$WB_TRAVAIL/rbd/MANIFESTE.tsv"
for spec in "${images[@]}"; do
  nom="${spec//\//__}"
  if ! rbdc snap ls "$spec" --format json | jq -e --arg s "$instantane" 'any(.[]; .name == $s)' >/dev/null; then
    rbdc snap create "$spec@$instantane"
  fi
  # Instantané de sauvegarde précédent : le plus récent « sauv-* » antérieur à celui du jour.
  precedent="$(rbdc snap ls "$spec" --format json \
    | jq -r --arg s "$instantane" '[.[].name | select(startswith("sauv-") and . < $s)] | sort | last // empty')"
  if [[ "$jour_semaine" == "$WB_JOUR_COMPLET" || -z "$precedent" ]]; then
    fichier="$WB_TRAVAIL/rbd/$nom.complet.$instantane.diff"
    rbdc export-diff "$spec@$instantane" "$fichier"
    type=complet
    precedent=""
  else
    fichier="$WB_TRAVAIL/rbd/$nom.$precedent.$instantane.diff"
    rbdc export-diff --from-snap "$precedent" "$spec@$instantane" "$fichier"
    type=incremental
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$spec" "$type" "${precedent:--}" "$instantane" \
    "$(stat -c %s "$fichier")" "$(sha256sum "$fichier" | cut -d' ' -f1)" >> "$WB_TRAVAIL/rbd/MANIFESTE.tsv"
  log "$spec : $type ${precedent:+depuis $precedent }($(stat -c %s "$fichier") octets)"
done

# --- 3. Configuration du cluster (commande forcée sur ceph01) ------------------------------------------
ssh -i "$WB_CLE_SSH" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 \
  -o UserKnownHostsFile=/etc/wb-backup/known_hosts -o StrictHostKeyChecking=yes \
  "wb-sauvegarde@$WB_EXPORT_HOTE" > "$WB_TRAVAIL/config/ceph-par1-config.tar" \
  || die "export de la configuration impossible depuis $WB_EXPORT_HOTE"
tar -tf "$WB_TRAVAIL/config/ceph-par1-config.tar" | grep -q 'auth.json' \
  || die "archive de configuration incomplète"
log "configuration : $(stat -c %s "$WB_TRAVAIL/config/ceph-par1-config.tar") octets"

# --- 4. Envoi vers PBS ------------------------------------------------------------------------------------
log "envoi vers PBS ($PBS_REPOSITORY, espace de noms $WB_NS)"
proxmox-backup-client backup "rbd.pxar:$WB_TRAVAIL/rbd" \
  --ns "$WB_NS" --backup-type host --backup-id "$WB_ID_RBD" --keyfile "$WB_CLE"
proxmox-backup-client backup "config.pxar:$WB_TRAVAIL/config" \
  --ns "$WB_NS" --backup-type host --backup-id "$WB_ID_CONFIG" --keyfile "$WB_CLE"

# --- 5. Après succès seulement : on ne garde que l'instantané du jour --------------------------------------
for spec in "${images[@]}"; do
  for ancien in $(rbdc snap ls "$spec" --format json \
      | jq -r --arg s "$instantane" '.[].name | select(startswith("sauv-") and . < $s)'); do
    rbdc snap rm "$spec@$ancien"
    log "$spec : instantané $ancien supprimé"
  done
done

log "terminé en $(($(date +%s) - debut)) s"
