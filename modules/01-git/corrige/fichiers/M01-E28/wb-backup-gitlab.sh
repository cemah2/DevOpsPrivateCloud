#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/wb-backup-gitlab.sh — sauvegarde applicative de GitLab vers PBS
# git01, M01-E28 (ticket PLAT-255). Lancé chaque nuit par wb-backup-gitlab.timer.
#
#  1. gitlab-backup create   : base, dépôts, pièces jointes, artefacts, wikis…
#  2. gitlab-ctl backup-etc  : /etc/gitlab (gitlab.rb, gitlab-secrets.json, certificats)
#  3. ce que GitLab ne sauvegarde pas : hooks globaux de Gitaly, clés d'hôte SSH
#  4. envoi vers PBS (PAR2), chiffré côté client, dans l'espace de noms par1/git01
#
# Secrets hors du script : /etc/wb-backup/pbs-git01.env (PBS_REPOSITORY,
# PBS_PASSWORD, PBS_FINGERPRINT) et la clé /etc/wb-backup/pbs-git01.key, tous
# deux root:root 0600. Code retour ≠ 0 au moindre échec (visible par systemd).
# =============================================================================
set -euo pipefail
umask 077

ENV_PBS=/etc/wb-backup/pbs-git01.env
CLE=/etc/wb-backup/pbs-git01.key
DONNEES=/var/opt/gitlab/backups          # gitlab_rails['backup_path'] (défaut)
CONFIG=/var/opt/gitlab/config_backup     # sortie de backup-etc (root seulement)
ENVOI=/var/opt/gitlab/wb-envoi           # même système de fichiers : liens physiques
NS=par1/git01
ID=git01

log() { printf 'wb-backup-gitlab: %s\n' "$*"; }
plus_recent() {   # plus_recent DOSSIER MOTIF — chemin du fichier le plus récent
  find "$1" -maxdepth 1 -type f -name "$2" -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-
}

[[ $EUID -eq 0 ]] || { log "à lancer en root"; exit 1; }
[[ -r "$ENV_PBS" && -r "$CLE" ]] || { log "secrets PBS absents ($ENV_PBS, $CLE)"; exit 1; }
# shellcheck source=/dev/null
source "$ENV_PBS"
export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT

debut=$(date +%s)

log "1/4 sauvegarde applicative (gitlab-backup create)"
# GZIP_RSYNCABLE : compression « stable » d'une nuit à l'autre, donc mieux dédupliquée par PBS.
gitlab-backup create CRON=1 GZIP_RSYNCABLE=yes
donnees="$(plus_recent "$DONNEES" '*_gitlab_backup.tar')"
[[ -n "$donnees" && "$(stat -c %Y "$donnees")" -ge "$debut" ]] || { log "archive applicative introuvable ou ancienne"; exit 1; }

log "2/4 configuration et secrets (gitlab-ctl backup-etc)"
gitlab-ctl backup-etc --backup-path "$CONFIG" --delete-old-backups
config="$(plus_recent "$CONFIG" 'gitlab_config_*.tar')"
[[ -n "$config" && "$(stat -c %Y "$config")" -ge "$debut" ]] || { log "archive de configuration introuvable"; exit 1; }

log "3/4 préparation de l'envoi"
rm -rf "$ENVOI"
install -d -o root -g root -m 0700 "$ENVOI"
ln "$donnees" "$ENVOI/"
ln "$config" "$ENVOI/"
# Hors du périmètre de GitLab : hooks globaux (E26) et clés d'hôte SSH (sinon,
# après une reconstruction, chaque poste refuse git01 : « host key changed »).
hors=(etc/ssh)
[[ -d /var/opt/gitlab/gitaly/custom_hooks ]] && hors+=(var/opt/gitlab/gitaly/custom_hooks)
tar -C / -cf "$ENVOI/hors-gitlab.tar" "${hors[@]}"
(cd "$ENVOI" && sha256sum -- * > SHA256SUMS)

log "4/4 envoi vers PBS ($PBS_REPOSITORY, espace de noms $NS)"
proxmox-backup-client backup "gitlab.pxar:$ENVOI" \
  --ns "$NS" --backup-type host --backup-id "$ID" --keyfile "$CLE"

rm -rf "$ENVOI"
log "terminé en $(( $(date +%s) - debut )) s : $(basename "$donnees"), $(basename "$config")"
