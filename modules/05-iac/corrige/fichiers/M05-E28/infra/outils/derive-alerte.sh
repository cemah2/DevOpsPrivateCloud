#!/usr/bin/env bash
# derive-alerte.sh — ticket GitLab « derive » à partir des rapports de derive.sh (M05-E28).
#
# Usage (job CI derive:alerte, après les jobs derive:<configuration>) :
#   outils/derive-alerte.sh rapports/derive-*/derive.json
#
# Un seul ticket ouvert à la fois, étiqueté « derive », dans plateforme/infra :
#   - non conforme et aucun ticket ouvert → création (tableau du rapport, lien vers le job) ;
#   - non conforme et un ticket ouvert    → commentaire (nouvelle détection) ;
#   - conforme et un ticket ouvert        → commentaire « conforme » (la fermeture reste une
#                                            décision humaine, après vérification) ;
#   - conforme et aucun ticket            → rien.
# Jeton : DERIVE_TOKEN, jeton d'accès de PROJET, rôle Reporter, portée api, expiration 1 an,
# variable CI protégée et masquée (registre des secrets). Rien d'autre que des tickets.
#
# Variables GitLab utilisées : CI_API_V4_URL, CI_PROJECT_ID, CI_PIPELINE_URL.
set -euo pipefail

: "${DERIVE_TOKEN:?DERIVE_TOKEN absent (variable CI protégée et masquée)}"
: "${CI_API_V4_URL:?à lancer dans un job GitLab}" "${CI_PROJECT_ID:?}" "${CI_PIPELINE_URL:?}"
[[ $# -gt 0 ]] || { echo "usage : $0 RAPPORT.json…" >&2; exit 2; }

# Fusion des rapports des différents jobs (une configuration chacun).
rapport="$(jq -s '{date: (map(.date) | max), configurations: (map(.configurations) | add)}' "$@")"
statut="$(jq -r '[.configurations[].statut] as $s
  | if ($s | index("erreur")) then "erreur" elif ($s | index("derive")) then "derive"
    elif ($s | index("ecart")) then "ecart" else "conforme" end' <<<"$rapport")"
echo "Résultat global : $statut"

api() {
  local methode="$1" chemin="$2"
  shift 2
  curl --fail --silent --show-error --max-time 30 -X "$methode" \
    -H "PRIVATE-TOKEN: $DERIVE_TOKEN" -H "Content-Type: application/json" \
    "$CI_API_V4_URL/projects/$CI_PROJECT_ID/$chemin" "$@"
}

tableau="$(jq -r '
  "| Configuration | Résultat | Détail |", "|---|---|---|",
  (.configurations[] | "| `\(.configuration)` | \(.statut) | " + (
     if .statut == "derive" then (.derives | map("`\(.adresse)` (\(.attributs | join(", ")))") | join("<br>"))
     elif .statut == "ecart" then (.ecarts | map("`\(.adresse)` : \(.actions | join("+"))") | join("<br>"))
     elif .statut == "erreur" then "plan impossible : voir le journal du job"
     else "—" end) + " |")' <<<"$rapport")"

texte="$(printf '**Détection du %s : %s**\n\n%s\n\nRapport complet (90 jours) : %s\n\n%s\n' \
  "$(jq -r .date <<<"$rapport")" "$statut" "$tableau" "$CI_PIPELINE_URL" \
  "dérive = modifié hors d'OpenTofu → réappliquer le code OU faire entrer le changement dans le code (MR) ; écart = MR fusionnée non appliquée → lancer le job apply ; erreur = la détection n'a pas pu conclure.")"

ouvert="$(api GET "issues?labels=derive&state=opened&per_page=1" | jq -r '.[0].iid // empty')"

if [[ "$statut" == "conforme" ]]; then
  if [[ -n "$ouvert" ]]; then
    api POST "issues/$ouvert/notes" --data "$(jq -n --arg b "$texte" '{body: $b}')" >/dev/null
    echo "Ticket #$ouvert commenté : détection conforme (à fermer après vérification)."
  fi
  exit 0
fi

if [[ -n "$ouvert" ]]; then
  api POST "issues/$ouvert/notes" --data "$(jq -n --arg b "$texte" '{body: $b}')" >/dev/null
  echo "Ticket #$ouvert commenté."
else
  iid="$(api POST issues --data "$(jq -n --arg t "Infrastructure : $statut détectée" --arg b "$texte" \
    '{title: $t, description: $b, labels: "derive"}')" | jq -r .iid)"
  echo "Ticket #$iid créé."
fi
