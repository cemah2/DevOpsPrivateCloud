#!/usr/bin/env bash
# rgw-preuves.sh — compartiment de preuves en verrouillage d'objets (F6-S02, PLAT-3602).
# Rangé dans plateforme/ceph (outils/), à côté de rgw-compartiment.sh (F2-S08) dont il reprend la
# construction ; lancé depuis adm01 par une personne de plateforme-admins (connectée à OpenBao par OIDC).
#
# Usage : rgw-preuves.sh creer
#         rgw-preuves.sh retention GOVERNANCE|COMPLIANCE JOURS
#         rgw-preuves.sh etat
#
# creer      utilisateurs RGW « preuves » (propriétaire, écriture par la collecte) et « preuves-lecture »
#            (auditeurs, contrôles), clés rangées dans OpenBao (kv/plateforme/preuves/rgw-ecriture et
#            rgw-lecture), compartiment créé AVEC le verrouillage d'objets (dès la création : aucun objet
#            n'y existe jamais sans protection ; RGW 20.2 accepterait aussi de l'activer après coup sur un
#            compartiment déjà versionné, jamais sur un compartiment non versionné), politique de compartiment
#            qui donne la lecture à « preuves-lecture ». Rétention par défaut posée à GOVERNANCE 1 jour
#            (phase d'essai). Idempotent : ne recrée ni utilisateur, ni clé, ni compartiment.
# retention  pose la rétention PAR DÉFAUT des nouveaux objets (les objets déjà écrits gardent la leur).
#            ⚠️ COMPLIANCE : aucun objet écrit ensuite ne pourra être supprimé ni écrasé avant
#            l'échéance, par personne, administrateur du compartiment compris. Demande une confirmation.
# etat       configuration du verrouillage, versionnage, politique, quota (sans secret).
#
# Le même script crée l'archive des journaux d'audit (F6-S08, SEC-3608) :
#   COMPARTIMENT=archive-audit PROPRIETAIRE=archive-audit LECTEUR=archive-audit-lecture \
#   KV_BASE=plateforme/archive-audit QUOTA=50G rgw-preuves.sh creer
#
# Codes retour : 0 succès, 1 erreur, 2 usage, 3 refus (confirmation absente).
set -euo pipefail

usage() { sed -n 's/^# Usage : /Usage : /p; s/^#         rgw-preuves/        rgw-preuves/p' "${BASH_SOURCE[0]}" >&2; exit 2; }
(($# >= 1)) || usage

COMPARTIMENT="${COMPARTIMENT:-preuves-conformite}"
PROPRIETAIRE="${PROPRIETAIRE:-preuves}"          # utilisateur RGW d'écriture (propriétaire du compartiment)
LECTEUR="${LECTEUR:-preuves-lecture}"            # utilisateur RGW de lecture (auditeurs, contrôles)
KV_BASE="${KV_BASE:-plateforme/preuves}"         # clés dans OpenBao : <KV_BASE>/rgw-ecriture et rgw-lecture
QUOTA="${QUOTA:-20G}"
CEPH_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
RGW_URL="${RGW_URL:-https://rgw.par1.medisphere.internal}"
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"
export AWS_DEFAULT_REGION=us-east-1 AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

for c in ssh jq aws bao; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 1; }
done
bao token lookup >/dev/null 2>&1 || { echo "pas de jeton OpenBao valide : bao login -method=oidc" >&2; exit 1; }

rgw() { ssh -n -o BatchMode=yes "$CEPH_ADMIN" sudo -n radosgw-admin "$@"; }

# utilisateur UID CHEMIN_KV NOM MAX_COMPARTIMENTS — crée l'utilisateur une fois, clés envoyées directement
# à OpenBao (MAX_COMPARTIMENTS : -1 interdit toute création de compartiment, code de RGW 20.2).
utilisateur() {
  if rgw user info --uid="$1" >/dev/null 2>&1; then
    echo "utilisateur RGW $1 : existe déjà (clés inchangées)"
    return 0
  fi
  rgw user create --uid="$1" --display-name="$3 (PLAT-3602)" --max-buckets="$4" |
    jq -e '{AWS_ACCESS_KEY_ID: .keys[0].access_key, AWS_SECRET_ACCESS_KEY: .keys[0].secret_key}
           | select(.AWS_SECRET_ACCESS_KEY != null)' |
    bao kv put -mount=kv "$2" - >/dev/null
  echo "utilisateur RGW $1 créé ; clés rangées dans kv/$2"
}

# en_tant_que CHEMIN_KV commande… — commande aws avec les clés lues dans OpenBao (sous-shell, jamais
# sur la ligne de commande ni affichées).
en_tant_que() {
  local kv="$1"
  shift
  (
    eval "$(bao kv get -format=json -mount=kv "$kv" |
      jq -r '.data.data | "export AWS_ACCESS_KEY_ID=\(.AWS_ACCESS_KEY_ID | @sh) AWS_SECRET_ACCESS_KEY=\(.AWS_SECRET_ACCESS_KEY | @sh)"')"
    aws --endpoint-url "$RGW_URL" "$@"
  )
}
ecr() { en_tant_que "$KV_BASE/rgw-ecriture" "$@"; }

regle() { # regle MODE JOURS — rétention par défaut des nouveaux objets
  ecr s3api put-object-lock-configuration --bucket "$COMPARTIMENT" --object-lock-configuration \
    "{\"ObjectLockEnabled\":\"Enabled\",\"Rule\":{\"DefaultRetention\":{\"Mode\":\"$1\",\"Days\":$2}}}"
}

case "$1" in
  creer)
    (($# == 1)) || usage
    utilisateur "$PROPRIETAIRE" "$KV_BASE/rgw-ecriture" "$COMPARTIMENT : écriture" 1
    utilisateur "$LECTEUR" "$KV_BASE/rgw-lecture" "$COMPARTIMENT : lecture (audit)" -1   # -1 : aucune création de compartiment
    rgw quota set --quota-scope=user --uid="$PROPRIETAIRE" --max-size="$QUOTA"
    rgw quota enable --quota-scope=user --uid="$PROPRIETAIRE"
    if ecr s3api head-bucket --bucket "$COMPARTIMENT" >/dev/null 2>&1; then
      echo "compartiment $COMPARTIMENT : existe déjà"
    else
      # Le verrouillage d'objets se demande À LA CRÉATION (en-tête x-amz-bucket-object-lock-enabled) ;
      # RGW active alors le versionnage du compartiment, qui ne peut plus être suspendu.
      ecr s3api create-bucket --bucket "$COMPARTIMENT" --object-lock-enabled-for-bucket >/dev/null
      echo "compartiment $COMPARTIMENT créé avec verrouillage d'objets"
      regle GOVERNANCE 1
      echo "rétention par défaut : GOVERNANCE 1 jour (phase d'essai)"
    fi
    # Lecture pour l'utilisateur de lecture : objets, versions, rétentions, configuration du verrou.
    # Format de principal d'un utilisateur RGW sans locataire : arn:aws:iam:::user/<uid>.
    ecr s3api put-bucket-policy --bucket "$COMPARTIMENT" --policy "$(jq -nc --arg b "$COMPARTIMENT" --arg l "$LECTEUR" '{
      Version: "2012-10-17",
      Statement: [{
        Sid: "LecturePreuves", Effect: "Allow",
        Principal: {AWS: ["arn:aws:iam:::user/\($l)"]},
        Action: ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetObject", "s3:GetObjectVersion",
                 "s3:GetObjectRetention", "s3:GetObjectLegalHold", "s3:GetBucketObjectLockConfiguration",
                 "s3:GetBucketVersioning"],
        Resource: ["arn:aws:s3:::\($b)", "arn:aws:s3:::\($b)/*"]}]}')"
    echo "politique de lecture posée pour $LECTEUR"
    "$0" etat
    ;;
  retention)
    (($# == 3)) || usage
    [[ "$2" =~ ^(GOVERNANCE|COMPLIANCE)$ && "$3" =~ ^[1-9][0-9]{0,4}$ ]] || usage
    if [[ "$2" == COMPLIANCE ]]; then
      echo "⚠️  COMPLIANCE $3 jours : chaque objet écrit à partir de maintenant sera INDESTRUCTIBLE pendant $3 jours,"
      echo "    y compris par toi, et occupera le RGW jusque-là. Une erreur de contenu ne se corrige que par un"
      echo "    nouvel objet (nouvelle version) : l'ancien reste."
      read -r -p "Tape « COMPLIANCE $3 » pour confirmer : " r
      [[ "$r" == "COMPLIANCE $3" ]] || { echo "non confirmé : rien n'est changé" >&2; exit 3; }
    fi
    regle "$2" "$3"
    echo "rétention par défaut : $2 $3 jours"
    ;;
  etat)
    (($# == 1)) || usage
    ecr s3api get-object-lock-configuration --bucket "$COMPARTIMENT"
    ecr s3api get-bucket-versioning --bucket "$COMPARTIMENT"
    ecr s3api get-bucket-policy --bucket "$COMPARTIMENT" --query Policy --output text | jq -c '.Statement[] | {Sid, Principal, n_actions: (.Action | length)}'
    rgw user info --uid="$PROPRIETAIRE" | jq '{user_id, max_buckets, user_quota}'
    ;;
  *) usage ;;
esac
