#!/usr/bin/env bash
# outils/instantane-vers-restauration.sh — amène un instantané de la grappe sur une VM de restauration
# (M25-E26, RB-252). Projet plateforme/secrets, lancé depuis adm01, dans le clone de plateforme/ansible
# pour l'accès au Vault « critique ».
#
# 1. choisit l'objet (le plus récent de horaire/, ou celui donné) dans s3://openbao-instantanes avec
#    l'identité de LECTURE (~/.config/workbook/s3-openbao-instantanes.env) ;
# 2. le télécharge, le déchiffre avec la clé PRIVÉE de restauration lue dans le Vault critique
#    (secrets/openbao-restauration.age), sans jamais l'écrire sur le disque de adm01 : tout passe
#    par des tubes ; la clé privée n'existe que dans un descripteur (process substitution) ;
# 3. l'écrit sur la cible dans /var/tmp/restauration.snap (admin, 600), en vérifiant qu'il s'agit
#    bien d'une archive d'instantané (meta.json, state.bin).
# La restauration elle-même (bao operator raft snapshot restore -force) est un geste humain : RB-252.
#
# Usage : outils/instantane-vers-restauration.sh <HÔTE-CIBLE> [CLÉ-OBJET]
#   ex. outils/instantane-vers-restauration.sh bao-restauration
set -Eeuo pipefail
umask 077

cible="${1:?usage : $0 <HÔTE-CIBLE> [CLÉ-OBJET]}"
objet="${2:-}"
env_s3="${WB_M25_S3_INSTANTANES_FILE:-$HOME/.config/workbook/s3-openbao-instantanes.env}"
point="${WB_M25_S3_URL:-https://s3-01.par1.medisphere.internal:8333}"
compartiment=openbao-instantanes
cle_privee_vault="${RESTAURATION_CLE:-secrets/openbao-restauration.age}"

erreur() { echo "instantane-vers-restauration : $*" >&2; exit 1; }
for c in aws age jq ssh uv tar; do command -v "$c" >/dev/null || erreur "outil manquant : $c"; done
[[ "$cible" != vault0[1-3]* && "$cible" != kms01* ]] || erreur "refus : $cible est un nœud de production (RB-252, restauration de la PRODUCTION : §6)"
[[ -r "$env_s3" ]] || erreur "identifiants S3 illisibles : $env_s3"
[[ -r "$cle_privee_vault" ]] || erreur "$cle_privee_vault introuvable (lance depuis la racine de plateforme/ansible)"

# shellcheck source=/dev/null
s3() { (set -a; . "$env_s3"; set +a; exec aws --endpoint-url "$point" --output json "$@" </dev/null); }

if [[ -z "$objet" ]]; then
  objet="$(s3 s3api list-objects-v2 --bucket "$compartiment" --prefix horaire/ \
    | jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .Key // empty')"
  [[ -n "$objet" ]] || erreur "aucun instantané dans s3://$compartiment/horaire/"
fi
echo "objet : s3://$compartiment/$objet"

# Téléchargement → déchiffrement → contrôle de forme → cible, dans un seul tube. La clé privée age
# est déchiffrée par ansible-vault dans un descripteur lu par age (-i), jamais dans un fichier.
s3 s3 cp "s3://$compartiment/$objet" - \
  | age -d -i <(uv run ansible-vault view "$cle_privee_vault" 2>/dev/null) \
  | ssh -o BatchMode=yes "admin@$cible" \
      'umask 077; cat > /var/tmp/restauration.snap && tar -tzf /var/tmp/restauration.snap | grep -qx state.bin && stat -c "%s octets reçus" /var/tmp/restauration.snap' \
  || erreur "échec (téléchargement, déchiffrement ou contrôle sur $cible)"
echo "prêt : $cible:/var/tmp/restauration.snap — suite : RB-252 §5 (snapshot restore -force), puis effacer le fichier."
