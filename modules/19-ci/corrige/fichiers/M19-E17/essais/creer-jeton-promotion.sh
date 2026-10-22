#!/usr/bin/env bash
# creer-jeton-promotion.sh — M19-E17 (PLAT-2017), à lancer sur adm01 : ~/m19/e17/creer-jeton-promotion.sh
# 1. protège main de mediagenda/deploiement (poussée : personne ; fusion : Maintainers) ;
# 2. crée le jeton de projet « ci-promotion » (Developer, api + write_repository, 90 jours) ;
# 3. le range dans la variable DEPLOIEMENT_TOKEN de mediagenda/api (protégée, masquée) ;
# 4. affiche ce qu'il faut reporter au registre des secrets (sans la valeur).
# Le jeton n'est jamais affiché, ni écrit sur le disque, ni passé en argument d'une commande.
# Jeton d'administration : personnel, portée « api », expiration le lendemain, dans
# ~/.config/workbook/gitlab-api-ecriture.token (600) ; révoque-le après la séance.
set -euo pipefail

GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
JETON_ADMIN="${GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-api-ecriture.token}"
DEPLOIEMENT="mediagenda%2Fdeploiement"
API_PROJET="mediagenda%2Fapi"
EXPIRATION="$(date -d '+90 days' +%F)"

[[ -r "$JETON_ADMIN" && "$(stat -c %a "$JETON_ADMIN")" == 600 ]] || { echo "jeton d'administration absent ou pas en 600 : $JETON_ADMIN" >&2; exit 2; }
# api ARGS… — curl authentifié ; l'en-tête est lu dans un descripteur (jamais dans ps).
api() { curl -sSf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_ADMIN")") "$@"; }

echo "1. Protection de main (fusion : Maintainers, poussée : personne)"
# En édition gratuite, PATCH ne change pas les niveaux d'accès : on retire puis on remet. La branche
# reste sans protection une fraction de seconde : à faire hors d'une fenêtre de promotion.
api -X DELETE "$GITLAB/projects/$DEPLOIEMENT/protected_branches/main" -o /dev/null || true
api -X POST "$GITLAB/projects/$DEPLOIEMENT/protected_branches" \
  --data name=main --data push_access_level=0 --data merge_access_level=40 --data allow_force_push=false \
  | jq -c '{name, push: [.push_access_levels[].access_level_description], merge: [.merge_access_levels[].access_level_description]}'
echo "   Maintainers du projet (et au-dessus) :"
api "$GITLAB/projects/$DEPLOIEMENT/members/all?per_page=100" | jq -r '.[] | select(.access_level >= 40) | "   - \(.username) (\(.access_level))"'

echo "2. Jeton de projet ci-promotion (expire le $EXPIRATION)"
reponse="$(api -X POST "$GITLAB/projects/$DEPLOIEMENT/access_tokens" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --arg e "$EXPIRATION" '{name: "ci-promotion", scopes: ["api", "write_repository"], access_level: 30, expires_at: $e}')")"
id_jeton="$(jq -r .id <<<"$reponse")"

echo "3. Variable DEPLOIEMENT_TOKEN de mediagenda/api (protégée, masquée)"
api -X DELETE "$GITLAB/projects/$API_PROJET/variables/DEPLOIEMENT_TOKEN" -o /dev/null 2>/dev/null || true
jq -r .token <<<"$reponse" | api -X POST "$GITLAB/projects/$API_PROJET/variables" \
  --data key=DEPLOIEMENT_TOKEN --data-urlencode value@- \
  --data protected=true --data masked=true --data raw=true \
  --data-urlencode "description=Jeton de projet ci-promotion de mediagenda/deploiement (id $id_jeton), expire le $EXPIRATION" \
  | jq -c '{key, protected, masked, raw}'
unset reponse

echo "4. Registre des secrets (docs/socle/registre-secrets.md) :"
echo "   DEPLOIEMENT_TOKEN — jeton de projet ci-promotion (id $id_jeton) de mediagenda/deploiement,"
echo "   Developer, api + write_repository, expire le $EXPIRATION ; lu par promouvoir-* (mediagenda/api)."
echo "   Rotation : POST /projects/$DEPLOIEMENT/access_tokens/$id_jeton/rotate, puis mise à jour de la variable."
