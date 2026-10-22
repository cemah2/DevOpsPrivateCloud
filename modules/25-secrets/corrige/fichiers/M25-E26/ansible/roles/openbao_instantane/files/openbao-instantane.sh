#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/openbao-instantane — instantané Raft de la grappe OpenBao, chiffré, envoyé vers s3-01
# (M25-E26, SEC-2626). Déployé sur vault01..03 par le rôle Ansible openbao_instantane ; lancé chaque
# heure par openbao-instantane.timer sur les TROIS nœuds, il ne travaille que sur le nœud ACTIF :
# les deux autres sortent en succès sans rien faire (la minuterie survit ainsi aux bascules).
#
# 1. le nœud local est-il actif ? (GET /v1/sys/leader, champ is_self, sans jeton) ;
# 2. connexion AppRole openbao-instantanes (role_id + secret_id de /etc/openbao/instantanes.env) :
#    jeton BATCH de 10 min, politique « read » sur sys/storage/raft/snapshot et rien d'autre ;
# 3. bao operator raft snapshot save vers un fichier temporaire (tmpfs privé de l'unité) ;
# 4. contrôle : archive gzip lisible contenant meta.json et state.bin ;
# 5. chiffrement age vers la clé PUBLIQUE de restauration (la privée n'est jamais ici) ;
# 6. envoi par rclone vers s3://openbao-instantanes/horaire/<AAAA-MM-JJ>/<nœud>-<horodatage>.snap.age,
#    relecture de la taille ;
# 7. trace du dernier succès (fichier + métrique pour le collecteur textfile de node_exporter).
#
# Aucune copie CLAIRE ne survit : l'instantané clair n'existe que dans /tmp privé de l'unité
# (PrivateTmp), effacé à la sortie. Les données d'un instantané sont chiffrées par la barrière, mais
# il contient aussi la configuration complète du coffre : il reste un fichier sensible.
# Secrets hors du script (root:root 0600) : /etc/openbao/instantanes.env (BAO_ROLE_ID,
# BAO_SECRET_ID) et /etc/openbao/s3.env (INSTANTANE_S3_CLE_ACCES, INSTANTANE_S3_CLE_SECRETE).
# Code retour ≠ 0 au moindre échec (systemd → OnFailure=ms-alerte@%n.service).
# =============================================================================
set -Eeuo pipefail
umask 077

CONF="${OPENBAO_INSTANTANE_CONF:-/etc/openbao/instantane.conf}"
ETAT="${OPENBAO_INSTANTANE_ETAT:-/var/lib/openbao-instantane}"

log() { printf 'openbao-instantane: %s\n' "$*"; }
die() { log "ERREUR : $*"; exit 1; }

[[ -r "$CONF" ]] || die "configuration absente : $CONF"
# shellcheck source=/dev/null
source "$CONF"
: "${INSTANTANE_NOEUD:?INSTANTANE_NOEUD manquant dans $CONF}"
: "${INSTANTANE_BAO_ADDR:?INSTANTANE_BAO_ADDR manquant dans $CONF}"
: "${INSTANTANE_S3_POINT:?INSTANTANE_S3_POINT manquant dans $CONF}"
: "${INSTANTANE_S3_COMPARTIMENT:?INSTANTANE_S3_COMPARTIMENT manquant dans $CONF}"
: "${INSTANTANE_AGE_DESTINATAIRE:?INSTANTANE_AGE_DESTINATAIRE manquant dans $CONF}"
INSTANTANE_CACERT="${INSTANTANE_CACERT:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
INSTANTANE_APPROLE="${INSTANTANE_APPROLE:-approle}"
INSTANTANE_TEXTFILE="${INSTANTANE_TEXTFILE:-}"

for outil in bao curl jq age rclone gzip tar; do
  command -v "$outil" >/dev/null || die "outil manquant : $outil"
done

secrets() { # secrets FICHIER — charge un fichier d'environnement root:600
  [[ -r "$1" ]] || die "secrets illisibles : $1"
  [[ "$(stat -c '%U:%a' "$1")" == root:600 ]] || die "$1 doit appartenir à root, mode 600"
  # shellcheck source=/dev/null
  source "$1"
}

# --- 1. Le nœud local est-il actif ? -------------------------------------------------------------------
# Adresse du nœud LOCAL (pas la VIP) : on veut savoir si CE nœud est l'actif.
leader="$(curl -sS --max-time 5 --cacert "$INSTANTANE_CACERT" "$INSTANTANE_BAO_ADDR/v1/sys/leader")" \
  || die "le nœud local ne répond pas sur $INSTANTANE_BAO_ADDR"
if ! jq -e '.is_self == true' >/dev/null <<<"$leader"; then
  log "nœud en attente (actif : $(jq -r '.leader_address // "inconnu"' <<<"$leader")) : rien à faire"
  exit 0
fi

# --- 2. Connexion AppRole (secret_id lu dans un fichier, passé par l'entrée standard de curl) ------------
secrets /etc/openbao/instantanes.env
: "${BAO_ROLE_ID:?BAO_ROLE_ID absent}"
: "${BAO_SECRET_ID:?BAO_SECRET_ID absent}"
BAO_TOKEN="$(jq -nc --arg r "$BAO_ROLE_ID" --arg s "$BAO_SECRET_ID" '{role_id: $r, secret_id: $s}' \
  | curl -sS --fail-with-body --max-time 10 --cacert "$INSTANTANE_CACERT" --data @- \
      "$INSTANTANE_BAO_ADDR/v1/auth/$INSTANTANE_APPROLE/login" | jq -r '.auth.client_token // empty')" \
  || die "connexion AppRole refusée"
[[ -n "$BAO_TOKEN" ]] || die "connexion AppRole : aucun jeton"
unset BAO_ROLE_ID BAO_SECRET_ID
export BAO_TOKEN BAO_ADDR="$INSTANTANE_BAO_ADDR" BAO_CACERT="$INSTANTANE_CACERT"

# --- 3. Instantané ----------------------------------------------------------------------------------------
travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
horo="$(date -u +%Y%m%dT%H%M%SZ)"
jour="$(date -u +%Y-%m-%d)"
nom="${INSTANTANE_NOEUD}-${horo}.snap"
debut=$(date +%s)
bao operator raft snapshot save "$travail/$nom" >/dev/null || die "bao operator raft snapshot save a échoué"
unset BAO_TOKEN # jeton batch : il expire seul ; plus besoin de lui

# --- 4. Contrôle de forme ------------------------------------------------------------------------------------
gzip -t "$travail/$nom" 2>/dev/null || die "instantané illisible (gzip)"
contenu="$(tar -tzf "$travail/$nom")" || die "instantané illisible (tar)"
if ! grep -qx 'meta.json' <<<"$contenu" || ! grep -qx 'state.bin' <<<"$contenu"; then
  die "instantané incomplet (meta.json ou state.bin absent)"
fi
taille_claire=$(stat -c %s "$travail/$nom")

# --- 5. Chiffrement côté client, puis effacement du clair ---------------------------------------------------
age -r "$INSTANTANE_AGE_DESTINATAIRE" -o "$travail/$nom.age" "$travail/$nom" || die "chiffrement age a échoué"
rm -f "$travail/$nom"
taille=$(stat -c %s "$travail/$nom.age")

# --- 6. Envoi et relecture -------------------------------------------------------------------------------------
secrets /etc/openbao/s3.env
export RCLONE_CONFIG_BAOS3_TYPE=s3
export RCLONE_CONFIG_BAOS3_PROVIDER=Other
export RCLONE_CONFIG_BAOS3_ENDPOINT="$INSTANTANE_S3_POINT"
export RCLONE_CONFIG_BAOS3_REGION=us-east-1
export RCLONE_CONFIG_BAOS3_FORCE_PATH_STYLE=true
export RCLONE_CONFIG_BAOS3_ACCESS_KEY_ID="${INSTANTANE_S3_CLE_ACCES:?clé ACCES absente}"
export RCLONE_CONFIG_BAOS3_SECRET_ACCESS_KEY="${INSTANTANE_S3_CLE_SECRETE:?clé secrète absente}"
unset INSTANTANE_S3_CLE_ACCES INSTANTANE_S3_CLE_SECRETE
cle="horaire/$jour/$nom.age"
rclone copyto --s3-no-check-bucket --retries 3 --low-level-retries 5 --contimeout 10s --timeout 120s \
  "$travail/$nom.age" "baos3:$INSTANTANE_S3_COMPARTIMENT/$cle" || die "envoi vers $cle a échoué"
vu="$(rclone lsjson "baos3:$INSTANTANE_S3_COMPARTIMENT/$cle" | jq -r '.[0].Size // empty')" || vu=""
[[ "$vu" == "$taille" ]] || die "objet $cle : taille relue « $vu », attendue $taille"

# --- 7. Traces ------------------------------------------------------------------------------------------------
maintenant=$(date +%s)
install -d -m 0700 "$ETAT"
printf '%s %s %s\n' "$maintenant" "$cle" "$taille_claire" >"$ETAT/dernier-succes.tmp"
mv -f "$ETAT/dernier-succes.tmp" "$ETAT/dernier-succes"
if [[ -n "$INSTANTANE_TEXTFILE" && -d "$INSTANTANE_TEXTFILE" ]]; then
  # Écriture atomique (le collecteur textfile ne doit jamais lire un fichier à moitié écrit).
  {
    echo '# HELP openbao_instantane_dernier_succes_secondes Horodatage du dernier instantané Raft envoyé (nœud actif).'
    echo '# TYPE openbao_instantane_dernier_succes_secondes gauge'
    echo "openbao_instantane_dernier_succes_secondes $maintenant"
    echo '# HELP openbao_instantane_taille_octets Taille de l instantané clair (avant chiffrement).'
    echo '# TYPE openbao_instantane_taille_octets gauge'
    echo "openbao_instantane_taille_octets $taille_claire"
  } >"$INSTANTANE_TEXTFILE/openbao_instantane.prom.$$"
  chmod 0644 "$INSTANTANE_TEXTFILE/openbao_instantane.prom.$$"
  mv -f "$INSTANTANE_TEXTFILE/openbao_instantane.prom.$$" "$INSTANTANE_TEXTFILE/openbao_instantane.prom"
fi
log "envoyé : s3://$INSTANTANE_S3_COMPARTIMENT/$cle ($taille octets chiffrés, $taille_claire en clair) en $((maintenant - debut)) s"
