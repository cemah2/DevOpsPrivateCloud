#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# revue-karim.sh — M01-E10 : Karim Benali relit ta merge request « fiche de la forge ».
#
# Usage (depuis adm01, à la racine du dépôt du workbook ou ailleurs) :
#   modules/01-git/ressources/M01-E10/revue-karim.sh             # Karim dépose sa revue
#   modules/01-git/ressources/M01-E10/revue-karim.sh --approuver # Karim relit tes corrections et approuve
#
# La MR attendue : projet plateforme/medisphere, branche source docs/fiche-forge, ouverte,
# contenant le nouveau fichier docs/socle/forge.md.
# Karim agit par un jeton d'emprunt d'identité créé avec ton jeton d'administration,
# valable un jour et révoqué à la fin du script.
set -euo pipefail

WB_EX="M01-E10"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"
trap gl_rendre_jetons EXIT

PROJET="plateforme/medisphere"
BRANCHE="docs/fiche-forge"
FICHIER="docs/socle/forge.md"
TITRE_SUGGERE="# Fiche de service — forge GitLab (git01)"

gl_prerequis_api git
pid="$(gl_id_projet "$PROJET")"
[[ -n "$pid" ]] || gl_erreur "projet $PROJET introuvable (voir M01-E06)"

mr="$(gl_api GET "projects/$pid/merge_requests?state=opened&source_branch=$(gl_enc "$BRANCHE")" | jq -c '.[0] // empty')"
[[ -n "$mr" ]] || gl_erreur "aucune MR ouverte depuis la branche $BRANCHE dans $PROJET"
iid="$(jq -r .iid <<<"$mr")"

gl_emprunter karim.benali JETON_KARIM

revue() {
  local detail base head start diffs
  detail="$(gl_api GET "projects/$pid/merge_requests/$iid")"
  base="$(jq -r .diff_refs.base_sha <<<"$detail")"
  head="$(jq -r .diff_refs.head_sha <<<"$detail")"
  start="$(jq -r .diff_refs.start_sha <<<"$detail")"
  [[ "$head" != null ]] || gl_erreur "GitLab n'a pas encore calculé le diff de la MR !$iid, réessaie dans une minute"

  diffs="$(gl_api GET "projects/$pid/merge_requests/$iid/diffs?per_page=100")"
  jq -e --arg f "$FICHIER" 'any(.[]; .new_path == $f and .new_file)' <<<"$diffs" >/dev/null \
    || gl_erreur "la MR !$iid ne crée pas le fichier $FICHIER"

  if gl_api GET "projects/$pid/merge_requests/$iid/discussions?per_page=100" \
       | jq -e '[.[].notes[] | select(.author.username == "karim.benali")] | length > 0' >/dev/null; then
    gl_msg "Karim a déjà relu la MR !$iid. Traite ses remarques, puis lance ce script avec --approuver."
    return 0
  fi

  # 1. Suggestion sur la première ligne du nouveau fichier
  local corps1
  corps1="$(printf '%s\n\n%s\n%s\n%s' \
    "Titre à aligner sur nos autres fiches de service (on les retrouve plus vite dans la recherche) :" \
    '```suggestion:-0+0' "$TITRE_SUGGERE" '```')"
  gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/discussions" \
    "$(jq -nc --arg b "$corps1" --arg base "$base" --arg head "$head" --arg start "$start" --arg f "$FICHIER" \
      '{body:$b, position:{position_type:"text", base_sha:$base, head_sha:$head, start_sha:$start,
        new_path:$f, old_path:$f, new_line:1}}')" >/dev/null

  # 2. Fil général : section manquante
  gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/discussions" \
    "$(jq -nc --arg b "Il manque l'essentiel pour l'astreinte : que fait-on quand la forge est indisponible ? Qui prévenir, où sont les sauvegardes, comment continuer à travailler en attendant (dépôts locaux, push différé). Ajoute une section « En cas d'indisponibilité », même courte." '{body:$b}')" >/dev/null

  # 3. Question ouverte
  gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/discussions" \
    "$(jq -nc --arg b "Question : pourquoi une fiche séparée plutôt qu'une ligne de plus dans \`inventaire.md\` ? Réponds ici, ça fixera la règle pour les prochaines fiches." '{body:$b}')" >/dev/null

  gl_msg "Karim a relu la MR !$iid : 3 fils de discussion ouverts. À toi de les traiter."
}

approuver() {
  local disc ouverts brut
  disc="$(gl_api GET "projects/$pid/merge_requests/$iid/discussions?per_page=100")"
  jq -e '[.[].notes[] | select(.author.username == "karim.benali")] | length > 0' <<<"$disc" >/dev/null \
    || gl_erreur "Karim n'a pas encore relu cette MR : lance d'abord le script sans option"
  ouverts="$(jq '[.[].notes[] | select(.resolvable and (.resolved | not))] | length' <<<"$disc")"
  if (( ouverts > 0 )); then
    gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/notes" \
      "$(jq -nc --arg b "Il reste $ouverts fil(s) non résolu(s) : je repasse quand tout est traité." '{body:$b}')" >/dev/null
    gl_msg "Karim n'approuve pas : $ouverts fil(s) encore ouvert(s)."
    exit 1
  fi
  brut="$(gl_api GET "projects/$pid/repository/files/$(gl_enc "$FICHIER")/raw?ref=$(gl_enc "$BRANCHE")")"
  if ! grep -qiE 'indisponib|en cas de panne' <<<"$brut"; then
    gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/notes" \
      "$(jq -nc --arg b "Je ne vois toujours pas la section sur l'indisponibilité de la forge dans la dernière version." '{body:$b}')" >/dev/null
    gl_msg "Karim n'approuve pas : la section demandée est absente de la branche."
    exit 1
  fi
  gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/approve" '{}' >/dev/null
  gl_api_jeton "$JETON_KARIM" POST "projects/$pid/merge_requests/$iid/notes" \
    "$(jq -nc --arg b "Merci, c'est bon pour moi. Tu peux fusionner." '{body:$b}')" >/dev/null
  gl_msg "Karim a approuvé la MR !$iid."
}

case "${1:-}" in
  "")           revue ;;
  --approuver)  approuver ;;
  *)            echo "Usage : $0 [--approuver]" >&2; exit 2 ;;
esac
