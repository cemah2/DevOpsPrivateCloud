#!/usr/bin/env bash
# outils/publier-secrets-registre.sh — plateforme/outils (M13-E03, PLAT-1403).
#
# Lit les secrets des robots dans l'état OpenTofu « registre » (chiffré) et les publie :
#   - ~/.config/workbook/harbor-checks.env (robot wb-checks, lu par lab/lib/check-lib.sh) ;
#   - ~/.config/workbook/harbor-moi.env (ton compte, mot de passe INITIAL, seulement s'il n'existe pas) ;
#   - variables de CI des groupes applicatifs : HARBOR_ROBOT_USER (protégée, non développée, NON
#     masquable : « $ »), HARBOR_ROBOT_TOKEN (protégée, masquée, non développée).
# Aucun secret en argument de commande : fichiers temporaires dans /dev/shm (mémoire), effacés.
#
# Usage (sur adm01, depuis la copie de travail de plateforme/infra) :
#   admin@adm01:~/src/infra$ . outils/charger-acces.sh      # TF_ENCRYPTION, accès S3 (M05)
#   admin@adm01:~/src/infra$ ~/src/outils/publier-secrets-registre.sh [--sans-ci]
set -euo pipefail

CFG="$HOME/.config/workbook"
GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_ADMIN="${WB_GITLAB_ADMIN_TOKEN_FILE:-$CFG/gitlab-admin.token}"
GROUPES=(mediagenda medidoc medinotif legacy)
MOI="${WB_MOI:-}"
SANS_CI=0
[[ "${1:-}" == "--sans-ci" ]] && SANS_CI=1

for o in tofu jq curl; do command -v "$o" >/dev/null || { echo "$o requis" >&2; exit 2; }; done
[[ -d registre ]] || { echo "À lancer depuis la racine de plateforme/infra (dossier registre/ absent)" >&2; exit 2; }
[[ -n "${TF_ENCRYPTION:-}" ]] || { echo "TF_ENCRYPTION absente : source d'abord outils/charger-acces.sh" >&2; exit 2; }

umask 077
mkdir -p "$CFG"
TMP="$(mktemp -d /dev/shm/registre.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

tofu -chdir=registre output -json robots > "$TMP/robots.json"
tofu -chdir=registre output -json mots_de_passe_initiaux > "$TMP/humains.json"

# ecrire_env FICHIER UTILISATEUR SECRET — fichier « HARBOR_USER=… HARBOR_PASSWORD=… » en 600.
# Valeurs entre apostrophes : le « $ » de « robot$… » n'est pas développé quand on source le fichier.
ecrire_env() {
  local f="$1" u="$2" s="$3"
  printf "HARBOR_USER='%s'\nHARBOR_PASSWORD='%s'\n" "$u" "$s" > "$f.tmp"
  chmod 600 "$f.tmp" && mv "$f.tmp" "$f"
  echo "écrit : $f (600)"
}

ecrire_env "$CFG/harbor-checks.env" \
  "$(jq -r '."wb-checks".utilisateur' "$TMP/robots.json")" \
  "$(jq -r '."wb-checks".secret' "$TMP/robots.json")"

if [[ -n "$MOI" && ! -e "$CFG/harbor-moi.env" ]]; then
  ecrire_env "$CFG/harbor-moi.env" "$MOI" "$(jq -r --arg m "$MOI" '.[$m]' "$TMP/humains.json")"
  echo "→ change ce mot de passe à ta première connexion, puis mets à jour $CFG/harbor-moi.env"
fi

(( SANS_CI )) && exit 0
[[ -r "$JETON_ADMIN" ]] || { echo "jeton d'administration GitLab illisible : $JETON_ADMIN" >&2; exit 2; }
printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_ADMIN")" > "$TMP/entete"

# variable_groupe GROUPE CLÉ FICHIER_VALEUR MASQUÉE — crée ou met à jour une variable de groupe.
variable_groupe() {
  local g="$1" cle="$2" fval="$3" masque="$4" url code
  url="$GITLAB_URL/api/v4/groups/$g/variables"
  code="$(curl -s -o /dev/null -w '%{http_code}' --header @"$TMP/entete" "$url/$cle")"
  local args=(--fail -s -o /dev/null --header @"$TMP/entete"
    --data-urlencode "value@$fval" --data "protected=true" --data "masked=$masque" --data "raw=true")
  if [[ "$code" == 200 ]]; then
    curl -X PUT "${args[@]}" "$url/$cle"
  else
    curl -X POST "${args[@]}" --data "key=$cle" "$url"
  fi
  echo "groupe $g : $cle (protégée, masquée=$masque, non développée)"
}

jq -j '."medisphere-ci".utilisateur' "$TMP/robots.json" > "$TMP/u"
jq -j '."medisphere-ci".secret' "$TMP/robots.json" > "$TMP/s"
for g in "${GROUPES[@]}"; do
  variable_groupe "$g" HARBOR_ROBOT_USER "$TMP/u" false
  variable_groupe "$g" HARBOR_ROBOT_TOKEN "$TMP/s" true
done
echo "Pense au registre des secrets : date d'expiration des robots (180 jours)."
