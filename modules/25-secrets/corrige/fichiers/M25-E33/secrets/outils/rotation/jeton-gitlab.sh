#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# outils/rotation/jeton-gitlab.sh — rotation SANS COUPURE d'un jeton d'accès de projet GitLab
# (M25-E33). On ne se sert PAS de l'API « rotate » (elle révoque l'ancien jeton à l'instant même :
# coupure jusqu'à ce que le consommateur relise le coffre) : on CRÉE un jeton neuf, on l'écrit dans le
# coffre, et l'ancien est révoqué par le job « verifier » (jeton-gitlab-revoquer.sh) une fois les
# consommateurs passés.
# Le secret décrit lui-même sa rotation (métadonnées personnalisées de kv/<CHEMIN-KV>) :
#   gitlab_projet (identifiant numérique), gitlab_portees (ex. read_repository), gitlab_niveau (10..50),
#   gitlab_jeton_id (identifiant du jeton courant, tenu à jour ici).
# Usage : jeton-gitlab.sh <CHEMIN-KV>
# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"
besoin bao jq curl
chemin="${1:?usage : $0 <CHEMIN-KV>}"
gl="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
meta="$(bao kv metadata get -mount=kv -format=json "$chemin")"
projet="$(jq -er '.data.custom_metadata.gitlab_projet' <<<"$meta")"
portees="$(jq -er '.data.custom_metadata.gitlab_portees' <<<"$meta")"
niveau="$(jq -er '.data.custom_metadata.gitlab_niveau' <<<"$meta")"
ancien="$(jq -r '.data.custom_metadata.gitlab_jeton_id // empty' <<<"$meta")"
# Durée de vie GitLab : période de rotation + 30 jours de marge (le jeton ne meurt jamais avant sa relève).
expire="$(date -u -d '+120 days' +%Y-%m-%d)"

corps="$(jq -nc --arg n "rotation-$(date -u +%Y%m%d)" --arg e "$expire" --arg p "$portees" --argjson a "$niveau" \
  '{name: $n, expires_at: $e, access_level: $a, scopes: ($p | split(","))}')"
reponse="$(kv_champ plateforme/rotation/gitlab jeton \
  | curl -sS --fail-with-body --max-time 20 -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(cat)") \
      -H 'Content-Type: application/json' -d "$corps" "$gl/api/v4/projects/$projet/access_tokens")" \
  || echec "création du jeton du projet $projet"
nouveau_id="$(jq -er '.id' <<<"$reponse")"
jq -jer '.token' <<<"$reponse" | kv_ecrire_champ "$chemin" jeton || echec "écriture dans kv/$chemin"
unset reponse
bao kv metadata patch -mount=kv -custom-metadata="gitlab_jeton_id=$nouveau_id" \
  -custom-metadata="gitlab_jeton_precedent=${ancien:-aucun}" "$chemin" >/dev/null
journal "projet $projet : jeton $nouveau_id créé (expire le $expire), précédent ${ancien:-aucun} à révoquer après vérification"
