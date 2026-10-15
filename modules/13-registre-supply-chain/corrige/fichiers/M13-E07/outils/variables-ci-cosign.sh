#!/usr/bin/env bash
# outils/variables-ci-cosign.sh — plateforme/outils (M13-E07). Publie la clé de signature de la CI :
#   COSIGN_PRIVATE_KEY : type FICHIER, protégée (une clé PEM multiligne ne peut pas être masquée) ;
#   COSIGN_PASSWORD    : protégée, masquée.
# dans les groupes applicatifs. La clé passe par un fichier temporaire EN MÉMOIRE (/dev/shm), effacé.
#   admin@adm01:~$ . ~/src/outils/cosign-cle.sh && ~/src/outils/variables-ci-cosign.sh
set -euo pipefail
: "${COSIGN_KEY:?source outils/cosign-cle.sh avant}"
: "${COSIGN_PASSWORD:?}"
GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
GROUPES=(mediagenda medidoc medinotif legacy)

umask 077
TMP="$(mktemp -d /dev/shm/cosign-ci.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON")" > "$TMP/entete"
printf '%s\n' "$COSIGN_KEY" > "$TMP/cle"
printf '%s' "$COSIGN_PASSWORD" > "$TMP/mdp"

# poser GROUPE CLÉ FICHIER TYPE MASQUÉE
poser() {
  local url="$GITLAB_URL/api/v4/groups/$1/variables" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --header @"$TMP/entete" "$url/$2")"
  local a=(--fail -s -o /dev/null --header @"$TMP/entete" --data-urlencode "value@$3"
           --data "variable_type=$4" --data "protected=true" --data "masked=$5" --data "raw=true")
  if [[ "$code" == 200 ]]; then curl -X PUT "${a[@]}" "$url/$2"; else curl -X POST "${a[@]}" --data "key=$2" "$url"; fi
  echo "groupe $1 : $2 ($4, protégée, masquée=$5)"
}
for g in "${GROUPES[@]}"; do
  poser "$g" COSIGN_PRIVATE_KEY "$TMP/cle" file false
  poser "$g" COSIGN_PASSWORD "$TMP/mdp" env_var true
done
