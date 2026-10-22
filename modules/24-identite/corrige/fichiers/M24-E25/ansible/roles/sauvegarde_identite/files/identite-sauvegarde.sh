#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/identite-sauvegarde — sauvegarde applicative de l'identité, chiffrée, envoyée
# vers s3-01 (M24-E25, PLAT-2525). Déployé par le rôle Ansible sauvegarde_identite sur idp01
# (mode keycloak) et ipa01 (mode freeipa) ; lancé chaque nuit par identite-sauvegarde.timer, ou à
# la demande (systemctl start identite-sauvegarde.service) avant tout changement risqué.
#
#   keycloak : pg_dump -Fc de la base (clés de signature, secrets des clients, OTP, comptes de
#              master, sessions persistées) ; contrôle par pg_restore --list.
#   freeipa  : ipa-backup --data --online (annuaire LDAP, sans arrêt des services). Une sauvegarde
#              COMPLÈTE (ipa-backup sans --data : configuration, CA et clés) arrête les services : elle
#              ne se fait pas chaque nuit, mais à la main avant chaque changement (RB-245) ; la nuit,
#              la configuration est couverte par la sauvegarde de VM (PBS, par1/identite).
#              Contrôle : fichier header présent dans l'archive.
#
# Chiffrement age vers une clé PUBLIQUE (la privée n'est jamais sur cet hôte) ; envoi par rclone,
# relecture de la taille de l'objet ; aucune copie claire conservée (dossier root 700 effacé par trap).
# Secrets hors du script : /etc/identite-sauvegarde/s3.env (root:root 0600). Jamais en argument.
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF=/etc/identite-sauvegarde/identite-sauvegarde.conf
SECRETS=/etc/identite-sauvegarde/s3.env
ETAT=/var/lib/identite-sauvegarde

log() { printf 'identite-sauvegarde: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root"
[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"
: "${IDENTITE_MODE:?IDENTITE_MODE (keycloak ou freeipa) manquant dans $CONF}"
: "${IDENTITE_HOTE:?IDENTITE_HOTE manquant dans $CONF}"
: "${IDENTITE_S3_POINT:?IDENTITE_S3_POINT manquant dans $CONF}"
: "${IDENTITE_S3_COMPARTIMENT:?IDENTITE_S3_COMPARTIMENT manquant dans $CONF}"
: "${IDENTITE_AGE_DESTINATAIRE:?IDENTITE_AGE_DESTINATAIRE manquant dans $CONF}"
IDENTITE_TRAVAIL="${IDENTITE_TRAVAIL:-/var/backups/identite}"
IDENTITE_BDD="${IDENTITE_BDD:-keycloak}"

[[ "$IDENTITE_AGE_DESTINATAIRE" == age1* ]] || die "IDENTITE_AGE_DESTINATAIRE n'est pas une clé publique age (age1…)"
[[ -r "$SECRETS" ]] || die "secrets S3 illisibles : $SECRETS"
[[ "$(stat -c '%U:%G:%a' "$SECRETS")" == root:root:600 ]] || die "$SECRETS doit appartenir à root:root, mode 600"
# shellcheck source=/dev/null
source "$SECRETS"
: "${IDENTITE_S3_CLE_ACCES:?clé IDENTITE_S3_CLE_ACCES absente de $SECRETS}"
: "${IDENTITE_S3_CLE_SECRETE:?clé secrète absente de $SECRETS}"

for outil in age rclone jq; do
  command -v "$outil" >/dev/null || die "outil manquant : $outil"
done

# rclone : distant « ids3 » décrit entièrement par l'environnement (aucun rclone.conf, aucun argument secret).
export RCLONE_CONFIG_IDS3_TYPE=s3
export RCLONE_CONFIG_IDS3_PROVIDER=Other
export RCLONE_CONFIG_IDS3_ENDPOINT="$IDENTITE_S3_POINT"
export RCLONE_CONFIG_IDS3_REGION=us-east-1
export RCLONE_CONFIG_IDS3_FORCE_PATH_STYLE=true
export RCLONE_CONFIG_IDS3_ACCESS_KEY_ID="$IDENTITE_S3_CLE_ACCES"
export RCLONE_CONFIG_IDS3_SECRET_ACCESS_KEY="$IDENTITE_S3_CLE_SECRETE"
unset IDENTITE_S3_CLE_ACCES IDENTITE_S3_CLE_SECRETE

install -d -o root -g root -m 0700 "$IDENTITE_TRAVAIL" "$ETAT"
travail="$(mktemp -d "$IDENTITE_TRAVAIL/.travail.XXXXXX")"
nettoyer() { rm -rf -- "$travail"; }
trap nettoyer EXIT

horo="$(date -u +%Y%m%dT%H%M%SZ)"
# Dossiers ipa-data-AAAA-MM-JJ-HH-MM-SS : l'ordre alphabétique est l'ordre chronologique.
dernier_ipa_data() { find /var/lib/ipa/backup -maxdepth 1 -type d -name 'ipa-data-*' 2>/dev/null | sort | tail -n 1; }
debut=$(date +%s)

case "$IDENTITE_MODE" in
  keycloak)
    command -v pg_dump >/dev/null || die "pg_dump absent"
    nom="keycloak-${IDENTITE_HOTE}-${horo}.dump"
    # Instantané transactionnel (MVCC) : cohérent sans arrêter Keycloak. En tant que postgres
    # (authentification « peer » par le socket local) : aucun mot de passe en jeu.
    runuser -u postgres -- pg_dump -Fc --no-password -d "$IDENTITE_BDD" >"$travail/$nom" \
      || die "pg_dump de $IDENTITE_BDD a échoué"
    # Contrôle : l'archive est lisible et contient les tables qui portent les secrets.
    liste="$(pg_restore --list "$travail/$nom")" || die "archive illisible (pg_restore --list)"
    for table in realm client component_config credential user_entity; do
      grep -Eq "TABLE DATA public ${table} " <<<"$liste" || die "table $table absente de l'archive"
    done
    ;;
  freeipa)
    command -v ipa-backup >/dev/null || die "ipa-backup absent"
    avant="$(dernier_ipa_data)"
    ipa-backup --data --online --quiet || die "ipa-backup --data --online a échoué"
    dossier="$(dernier_ipa_data)"
    [[ -n "$dossier" && "$dossier" != "$avant" ]] || die "aucun nouveau dossier ipa-data-* produit"
    [[ -s "$dossier/header" ]] || die "$dossier/header absent ou vide"
    nom="freeipa-${IDENTITE_HOTE}-${horo}.tar"
    tar -C "$(dirname "$dossier")" -cf "$travail/$nom" "$(basename "$dossier")" || die "archivage de $dossier a échoué"
    tar -tf "$travail/$nom" | grep -q '/header$' || die "archive sans fichier header"
    # La copie locale d'ipa-backup reste dans /var/lib/ipa/backup (root 700) : on n'en garde que
    # IDENTITE_GARDER_LOCAL (restauration rapide sur place).
    mapfile -t anciens < <(find /var/lib/ipa/backup -maxdepth 1 -type d -name 'ipa-data-*' | sort -r \
      | tail -n +"$(( ${IDENTITE_GARDER_LOCAL:-3} + 1 ))")
    for d in "${anciens[@]}"; do rm -rf -- "$d"; done
    ;;
  *)
    die "IDENTITE_MODE inconnu : $IDENTITE_MODE (keycloak ou freeipa)"
    ;;
esac
taille_claire=$(stat -c %s "$travail/$nom")
log "archive prête : $nom ($taille_claire octets)"

# Chiffrement côté client, puis effacement immédiat de la copie claire.
age -r "$IDENTITE_AGE_DESTINATAIRE" -o "$travail/$nom.age" "$travail/$nom" || die "chiffrement age a échoué"
rm -f -- "$travail/$nom"
taille=$(stat -c %s "$travail/$nom.age")

cle="${IDENTITE_HOTE}/${nom}.age"
rclone copyto --s3-no-check-bucket --retries 3 --low-level-retries 5 --contimeout 10s --timeout 300s \
  "$travail/$nom.age" "ids3:$IDENTITE_S3_COMPARTIMENT/$cle" || die "envoi vers $cle a échoué"
vu="$(rclone lsjson "ids3:$IDENTITE_S3_COMPARTIMENT/$cle" | jq -r '.[0].Size // empty')" || vu=""
[[ "$vu" == "$taille" ]] || die "objet $cle : taille relue « $vu », attendue $taille"
log "envoyé : s3://$IDENTITE_S3_COMPARTIMENT/$cle ($taille octets)"

# Trace du dernier succès (lue par la supervision et par lab/bin/check 24 25) : époque, objet, taille.
printf '%s %s %s\n' "$(date +%s)" "$cle" "$taille" >"$ETAT/dernier-succes.tmp"
mv -f "$ETAT/dernier-succes.tmp" "$ETAT/dernier-succes"
log "terminé en $(( $(date +%s) - debut )) s"
