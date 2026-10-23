#!/usr/bin/env bash
# pra-miroirs.sh — écart entre les miroirs de adm02 et GitLab (F5-S04), pour node_exporter.
#   pra_miroir_ecart{projet="…"}                1 si main du miroir ≠ main de GitLab, 0 sinon
#   pra_miroir_commit_gitlab_horodatage{projet} date du dernier commit de main dans GitLab (epoch)
#   pra_miroir_mesure_reussie{projet}           0 si GitLab ou le miroir n'a pas pu être lu
# Un écart récent est normal (la poussée suit de quelques secondes) : c'est la règle d'alerte qui
# tolère une durée (PraMiroirEnEcart). En PRA, GitLab est injoignable : mesure_reussie = 0 partout,
# et l'alerte correspondante est sans objet (elle part avec mon01).
set -uo pipefail
: "${MIROIRS_RACINE:?}" "${MIROIRS_PROJETS:?}" "${GITLAB_URL:?}" "${GITLAB_JETON_FICHIER:?}" "${PRA_TEXTFILE:?}"
tmp="$(mktemp "$PRA_TEXTFILE/.pra_miroirs.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
echo "# TYPE pra_miroir_ecart gauge" >"$tmp"
for p in $MIROIRS_PROJETS; do
  enc="$(jq -rn --arg s "$p" '$s|@uri')"
  if g="$(curl -sf --max-time 10 -H "PRIVATE-TOKEN: $(<"$GITLAB_JETON_FICHIER")" \
        "$GITLAB_URL/api/v4/projects/$enc/repository/branches/main")" \
     && m="$(git --git-dir="$MIROIRS_RACINE/$p.git" rev-parse --verify -q refs/heads/main)"; then
    sha="$(jq -r .commit.id <<<"$g")"
    t="$(date -d "$(jq -r .commit.committed_date <<<"$g")" +%s)"
    {
      printf 'pra_miroir_ecart{projet="%s"} %d\n' "$p" "$([[ "$sha" == "$m" ]] && echo 0 || echo 1)"
      printf 'pra_miroir_commit_gitlab_horodatage{projet="%s"} %s\n' "$p" "$t"
      printf 'pra_miroir_mesure_reussie{projet="%s"} 1\n' "$p"
    } >>"$tmp"
  else
    printf 'pra_miroir_mesure_reussie{projet="%s"} 0\n' "$p" >>"$tmp"
  fi
done
chmod 0644 "$tmp"
mv "$tmp" "$PRA_TEXTFILE/pra_miroirs.prom"
trap - EXIT
