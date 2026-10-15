#!/usr/bin/env bash
# outils/creer-renovate-bot.sh — plateforme/outils (M13-E11, PLAT-1411).
# Crée (si besoin) l'utilisateur GitLab renovate-bot, non administrateur, lui donne le rôle
# Developer sur les projets traités, crée un jeton personnel (portée api, expiration dans 180 jours)
# et le pose dans la variable RENOVATE_TOKEN (protégée, masquée) de plateforme/renovate.
# Le jeton ne s'affiche jamais : fichiers temporaires en mémoire (/dev/shm), effacés.
#   admin@adm01:~$ ~/src/outils/creer-renovate-bot.sh
set -euo pipefail
GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
PROJETS=(mediagenda/api medidoc/medidoc medinotif/worker legacy/legacy-rdv plateforme/ci-templates)
API="$GITLAB_URL/api/v4"
umask 077
TMP="$(mktemp -d /dev/shm/renovate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON")" > "$TMP/entete"
api() { curl --fail -s --header @"$TMP/entete" "$@"; }
uri() { jq -rn --arg v "$1" '$v | @uri'; }

uid="$(api "$API/users?username=renovate-bot" | jq -r '.[0].id // empty')"
if [[ -z "$uid" ]]; then
  # Mot de passe aléatoire jamais utilisé (le bot ne se connecte qu'avec son jeton).
  python3 -c 'import secrets; print(secrets.token_urlsafe(32) + "Aa1")' > "$TMP/mdp"
  uid="$(api -X POST "$API/users" --data username=renovate-bot --data name="Renovate Bot" \
    --data email=renovate-bot@medisphere.internal --data skip_confirmation=true --data admin=false \
    --data-urlencode "password@$TMP/mdp" | jq -r .id)"
  echo "renovate-bot créé (id $uid)"
fi

for p in "${PROJETS[@]}"; do
  # 30 = Developer. 409 si déjà membre : on met à jour le niveau.
  api -X POST "$API/projects/$(uri "$p")/members" --data user_id="$uid" --data access_level=30 >/dev/null \
    || api -X PUT "$API/projects/$(uri "$p")/members/$uid" --data access_level=30 >/dev/null
  echo "renovate-bot : Developer sur $p"
done

expire="$(date -d '+180 days' +%F)"
api -X POST "$API/users/$uid/personal_access_tokens" --data name="renovate-$(date +%F)" \
  --data "scopes[]=api" --data expires_at="$expire" | jq -j .token > "$TMP/jeton"
pid="$(api "$API/projects/$(uri plateforme/renovate)" | jq -r .id)"
if api "$API/projects/$pid/variables/RENOVATE_TOKEN" >/dev/null 2>&1; then m=PUT; u="$API/projects/$pid/variables/RENOVATE_TOKEN"
else m=POST; u="$API/projects/$pid/variables"; fi
api -X "$m" "$u" --data key=RENOVATE_TOKEN --data-urlencode "value@$TMP/jeton" \
  --data protected=true --data masked=true --data raw=true >/dev/null
echo "RENOVATE_TOKEN posée (expire le $expire) : inscris la date au registre des secrets."
