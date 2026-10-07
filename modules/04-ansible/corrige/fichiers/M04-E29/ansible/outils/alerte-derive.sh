#!/usr/bin/env bash
# outils/alerte-derive.sh — ouvre ou complète le ticket « dérive » du projet (M04-E29)
#
# Usage (job CI) : outils/alerte-derive.sh RESUME_JSON
# Entrées : DERIVE_TOKEN (variable CI protégée, masquée : jeton d'accès de PROJET « bot-derive »,
#           rôle Reporter, portée api), et les variables prédéfinies CI_API_V4_URL,
#           CI_PROJECT_ID, CI_JOB_URL.
# Un seul ticket ouvert étiqueté « derive » : s'il existe, un commentaire y est ajouté,
# sinon il est créé. Le ticket ne contient que des noms d'hôtes et des liens : jamais un
# extrait du journal (il pourrait contenir un diff sensible).
set -euo pipefail

resume="${1:-}"
[[ -r "$resume" ]] || { echo "Usage : $0 RESUME_JSON" >&2; exit 4; }
for v in DERIVE_TOKEN CI_API_V4_URL CI_PROJECT_ID CI_JOB_URL; do
  [[ -n "${!v:-}" ]] || { echo "Variable absente : $v" >&2; exit 4; }
done

# Le jeton passe par un fichier d'en-tête (curl -H @fichier) : jamais dans la ligne de commande.
entete="$(mktemp)"
trap 'rm -f "$entete"' EXIT
printf 'PRIVATE-TOKEN: %s\n' "$DERIVE_TOKEN" >"$entete"
api="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

verdict="$(jq -r '.verdict // "inconnu"' "$resume")"
case "$verdict" in
  erreur) titre="Détection de dérive en échec (hôte injoignable ou tâche en erreur)" ;;
  *) titre="Dérive de configuration du socle" ;;
esac
corps="$(jq -r --arg job "$CI_JOB_URL" '
  "**Détection du \(.debut // "?")** — verdict : **\(.verdict // "?")** (commit \(.commit // "?"))\n\n" +
  "- Hôtes qui changeraient : \((.hotes_changes // []) | if length > 0 then join(", ") else "aucun" end)\n" +
  "- Hôtes en échec ou injoignables : \((.hotes_en_echec // []) | if length > 0 then join(", ") else "aucun" end)\n" +
  "- Tâches qui changeraient (total) : \(.changed // "?")\n\n" +
  "Rapport complet (journal, JUnit) : \($job)/artifacts/browse/rapports/\n\n" +
  "À faire : trouver la cause (modification manuelle ? paquet ? rôle non appliqué ?), puis " +
  "corriger PAR UNE APPLICATION (job appliquer) ou par une MR si la dérive doit devenir la règle."' "$resume")"

ouvert="$(curl -fsS -H @"$entete" "$api/issues?labels=derive&state=opened&per_page=1" | jq -r '.[0].iid // empty')"
if [[ -n "$ouvert" ]]; then
  jq -n --arg body "$corps" '{body: $body}' \
    | curl -fsS -H @"$entete" -H 'Content-Type: application/json' --data @- \
        "$api/issues/$ouvert/notes" >/dev/null
  echo "Commentaire ajouté au ticket #$ouvert (verdict : $verdict)."
else
  jq -n --arg body "$corps" --arg titre "$titre" \
      '{title: $titre, description: $body, labels: "derive"}' \
    | curl -fsS -H @"$entete" -H 'Content-Type: application/json' --data @- \
        "$api/issues" | jq -r '"Ticket #\(.iid) créé : \(.web_url)"'
fi
