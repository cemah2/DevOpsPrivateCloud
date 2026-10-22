#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# outils/rotation/controle-ages.sh — âge de chaque secret de kv/plateforme/ comparé à sa période
# (métadonnées personnalisées « rotation », durée Go : 720h, 2160h…) et propriétaire présent (M25-E33).
# L'âge est celui de la VERSION COURANTE (versions[n].created_time) : « updated_time » bouge aussi
# quand on modifie seulement les métadonnées (vérifié sur OpenBao 2.6.4/2.7.1) et mentirait.
# Échec (code 1) si un secret n'a pas de période ou de propriétaire, ou a dépassé sa période ;
# avertissement si moins de 15 jours restent. Rapport : rapport-ages.tsv (artefact du job).
# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"
besoin bao jq
racine="${1:-plateforme/}"
rapport="${RAPPORT:-rapport-ages.tsv}"
maintenant=$(date -u +%s)
printf 'secret\tproprietaire\tperiode_h\tage_j\tetat\n' >"$rapport"
ko=0

# feuilles CHEMIN/ — chemins des secrets (récursif), un par ligne.
feuilles() {
  local p="$1" k
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    if [[ "$k" == */ ]]; then feuilles "$p$k"; else printf '%s%s\n' "$p" "$k"; fi
  done < <(bao kv list -mount=kv -format=json "$p" 2>/dev/null | jq -r '.[]')
}

while IFS= read -r s; do
  m="$(bao kv metadata get -mount=kv -format=json "$s" | jq -c '.data')"
  prop="$(jq -r '.custom_metadata.proprietaire // empty' <<<"$m")"
  per="$(jq -r '.custom_metadata.rotation // empty' <<<"$m")"
  cree="$(jq -r '.versions[(.current_version | tostring)].created_time' <<<"$m")"
  age_s=$(( maintenant - $(date -u -d "$cree" +%s) ))
  if [[ -z "$prop" || ! "$per" =~ ^[0-9]+h$ ]]; then
    etat="SANS-METADONNEES"; ko=1; per_h="-"
  else
    per_h="${per%h}"
    if (( age_s > per_h * 3600 )); then etat="EN-RETARD"; ko=1
    elif (( age_s > per_h * 3600 - 15 * 86400 )); then etat="BIENTOT"
    else etat="OK"; fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$s" "${prop:--}" "$per_h" "$(( age_s / 86400 ))" "$etat" >>"$rapport"
done < <(feuilles "$racine")

column -t -s $'\t' "$rapport" 2>/dev/null || cat "$rapport"
(( ko == 0 )) || echec "secrets sans métadonnées ou en retard (voir $rapport) : RB-254"
journal "tous les secrets de kv/$racine sont dans leur période"
