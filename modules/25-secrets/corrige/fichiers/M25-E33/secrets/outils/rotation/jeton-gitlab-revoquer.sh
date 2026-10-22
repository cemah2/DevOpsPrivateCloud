#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# outils/rotation/jeton-gitlab-revoquer.sh — révoque le jeton GitLab PRÉCÉDENT d'un secret tourné par
# jeton-gitlab.sh, après vérification que le nouveau fonctionne (M25-E33). Usage : <CHEMIN-KV>
# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"
besoin bao jq curl
chemin="${1:?usage : $0 <CHEMIN-KV>}"
gl="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
meta="$(bao kv metadata get -mount=kv -format=json "$chemin")"
projet="$(jq -er '.data.custom_metadata.gitlab_projet' <<<"$meta")"
precedent="$(jq -r '.data.custom_metadata.gitlab_jeton_precedent // "aucun"' <<<"$meta")"
# Le nouveau jeton fonctionne-t-il ? (lecture du projet avec lui)
kv_champ "$chemin" jeton | curl -sS --fail-with-body --max-time 20 -o /dev/null \
  -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(cat)") "$gl/api/v4/projects/$projet" \
  || echec "le nouveau jeton de kv/$chemin ne lit pas le projet $projet : NE PAS révoquer l'ancien"
if [[ "$precedent" != aucun ]]; then
  kv_champ plateforme/rotation/gitlab jeton \
    | curl -sS --fail-with-body --max-time 20 -o /dev/null -X DELETE \
        -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(cat)") "$gl/api/v4/projects/$projet/access_tokens/$precedent" \
    || echec "révocation du jeton $precedent"
  bao kv metadata patch -mount=kv -custom-metadata=gitlab_jeton_precedent=aucun "$chemin" >/dev/null
  journal "projet $projet : jeton $precedent révoqué"
fi
