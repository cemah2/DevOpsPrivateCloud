#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/etcd-instantane — instantané etcd du membre LOCAL, chiffré, envoyé vers s3-01
# (M14-E24, PLAT-1524). Déployé sur k8s-cp01..03 par le rôle Ansible etcd_instantane ;
# lancé chaque heure par etcd-instantane.timer (minute décalée par nœud) ou à la demande
# (systemctl start etcd-instantane.service, voir plateforme/k8s outils/etcd-instantane.sh).
#
# 1. etcdctl snapshot save depuis https://127.0.0.1:2379 (membre local) ;
# 2. etcdutl snapshot status : l'instantané est lisible, révision > 0 ;
# 3. copie locale claire dans ETCD_LOCAL (root 700, rétention ETCD_GARDER fichiers) ;
# 4. chiffrement age vers la clé PUBLIQUE ETCD_AGE_DESTINATAIRE (la clé privée n'est jamais ici) ;
# 5. envoi par rclone vers s3://etcd-k8s-par1/horaire/<nœud>/… (et quotidien/ à l'heure
#    ETCD_HEURE_QUOTIDIEN), contrôle de la taille de l'objet envoyé ;
# 6. trace du dernier succès dans /var/lib/etcd-instantane/dernier-succes.
#
# Secrets hors du script : /etc/etcd-instantane/s3.env (root:root 0600) — ETCD_S3_CLE_ACCES,
# ETCD_S3_CLE_SECRETE. Ils ne sont passés à rclone que par l'environnement, jamais en argument
# (visibles sinon dans ps) et jamais journalisés.
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF=/etc/etcd-instantane/etcd-instantane.conf
SECRETS=/etc/etcd-instantane/s3.env
ETAT=/var/lib/etcd-instantane

log() { printf 'etcd-instantane: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"
: "${ETCD_NOEUD:?ETCD_NOEUD manquant dans $CONF}"
: "${ETCD_S3_POINT:?ETCD_S3_POINT manquant dans $CONF}"
: "${ETCD_S3_COMPARTIMENT:?ETCD_S3_COMPARTIMENT manquant dans $CONF}"
: "${ETCD_AGE_DESTINATAIRE:?ETCD_AGE_DESTINATAIRE manquant dans $CONF}"
ETCD_LOCAL="${ETCD_LOCAL:-/var/backups/etcd}"
ETCD_GARDER="${ETCD_GARDER:-6}"
ETCD_HEURE_QUOTIDIEN="${ETCD_HEURE_QUOTIDIEN:-03}"
ETCD_PKI="${ETCD_PKI:-/etc/kubernetes/pki/etcd}"

[[ -r "$SECRETS" ]] || die "secrets S3 illisibles : $SECRETS"
[[ "$(stat -c '%U:%a' "$SECRETS")" == root:600 ]] || die "$SECRETS doit appartenir à root, mode 600"
# shellcheck source=/dev/null
source "$SECRETS"
: "${ETCD_S3_CLE_ACCES:?clé ETCD_S3_CLE_ACCES absente de $SECRETS}"
: "${ETCD_S3_CLE_SECRETE:?clé secrète absente de $SECRETS}"

for outil in etcdctl etcdutl age rclone jq; do
  command -v "$outil" >/dev/null || die "outil manquant : $outil"
done

# --- etcdctl : membre local, certificat CLIENT de contrôle de santé (signé par la CA d'etcd) ------
# etcd de kubeadm n'active pas l'authentification par utilisateur : tout certificat client signé par
# etcd-ca a tous les droits. Celui-ci est fait pour les clients locaux ; on ne copie aucune clé.
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT="$ETCD_PKI/ca.crt"
export ETCDCTL_CERT="$ETCD_PKI/healthcheck-client.crt"
export ETCDCTL_KEY="$ETCD_PKI/healthcheck-client.key"
export ETCDCTL_DIAL_TIMEOUT=5s
export ETCDCTL_COMMAND_TIMEOUT=60s

# --- rclone : distant « etcds3 » décrit entièrement par l'environnement (aucun fichier rclone.conf) --
export RCLONE_CONFIG_ETCDS3_TYPE=s3
export RCLONE_CONFIG_ETCDS3_PROVIDER=Other
export RCLONE_CONFIG_ETCDS3_ENDPOINT="$ETCD_S3_POINT"
export RCLONE_CONFIG_ETCDS3_REGION=us-east-1
export RCLONE_CONFIG_ETCDS3_FORCE_PATH_STYLE=true
export RCLONE_CONFIG_ETCDS3_ACCESS_KEY_ID="$ETCD_S3_CLE_ACCES"
export RCLONE_CONFIG_ETCDS3_SECRET_ACCESS_KEY="$ETCD_S3_CLE_SECRETE"
unset ETCD_S3_CLE_ACCES ETCD_S3_CLE_SECRETE

install -d -o root -g root -m 0700 "$ETCD_LOCAL" "$ETAT"
travail="$(mktemp -d "$ETCD_LOCAL/.travail.XXXXXX")"
trap 'rm -rf "$travail"' EXIT

horo="$(date -u +%Y%m%dT%H%M%SZ)"
nom="etcd-${ETCD_NOEUD}-${horo}.db"
debut=$(date +%s)

# --- 1. Le membre local doit être sain (sinon on sauvegarderait un membre en retard) ------------------
etcdctl endpoint health >/dev/null 2>&1 || die "le membre local ne répond pas sainement (endpoint health)"

# --- 2. Instantané ----------------------------------------------------------------------------------
etcdctl snapshot save "$travail/$nom" >/dev/null || die "etcdctl snapshot save a échoué"
statut="$(etcdutl snapshot status "$travail/$nom" -w json)" || die "instantané illisible (etcdutl snapshot status)"
revision="$(jq -er '.revision' <<<"$statut")" || die "révision introuvable dans le statut"
cles="$(jq -er '.totalKey' <<<"$statut")" || cles="?"
[[ "$revision" =~ ^[0-9]+$ && "$revision" -gt 0 ]] || die "révision invalide : $revision"
taille_db=$(stat -c %s "$travail/$nom")
log "instantané pris : $nom, révision $revision, $cles clés, $taille_db octets"

# --- 3. Copie locale claire (restauration rapide) et rétention ---------------------------------------
cp --preserve=mode "$travail/$nom" "$ETCD_LOCAL/$nom"
mapfile -t anciens < <(find "$ETCD_LOCAL" -maxdepth 1 -type f -name 'etcd-*.db' -printf '%T@ %p\n' \
  | sort -rn | awk -v n="$ETCD_GARDER" 'NR > n { print $2 }')
for f in "${anciens[@]}"; do rm -f -- "$f"; done

# --- 4. Chiffrement côté client -----------------------------------------------------------------------
age -r "$ETCD_AGE_DESTINATAIRE" -o "$travail/$nom.age" "$travail/$nom" || die "chiffrement age a échoué"
taille=$(stat -c %s "$travail/$nom.age")

# --- 5. Envoi et contrôle --------------------------------------------------------------------------------
envoyer() { # envoyer PRÉFIXE
  local cle="$1/$ETCD_NOEUD/$nom.age" vu
  rclone copyto --s3-no-check-bucket --retries 3 --low-level-retries 5 --contimeout 10s --timeout 120s \
    "$travail/$nom.age" "etcds3:$ETCD_S3_COMPARTIMENT/$cle" || die "envoi vers $cle a échoué"
  vu="$(rclone lsjson "etcds3:$ETCD_S3_COMPARTIMENT/$cle" | jq -r '.[0].Size // empty')" || vu=""
  [[ "$vu" == "$taille" ]] || die "objet $cle : taille relue « $vu », attendue $taille"
  log "envoyé : s3://$ETCD_S3_COMPARTIMENT/$cle ($taille octets)"
  dernier_objet="$cle"
}
dernier_objet=""
envoyer horaire
if [[ "$(date +%H)" == "$ETCD_HEURE_QUOTIDIEN" ]]; then
  envoyer quotidien
fi

# --- 6. Trace du dernier succès (lue par la supervision et par lab/bin/check 14 24) -------------------------
printf '%s %s %s\n' "$(date +%s)" "$dernier_objet" "$revision" >"$ETAT/dernier-succes.tmp"
mv -f "$ETAT/dernier-succes.tmp" "$ETAT/dernier-succes"
log "terminé en $(( $(date +%s) - debut )) s"
