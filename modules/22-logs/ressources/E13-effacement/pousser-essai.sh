#!/usr/bin/env bash
# pousser-essai.sh — M22-E13 : pousse quelques lignes de journal FACTICES dans le locataire « essai »
# de Loki, dont deux qui contiennent un identifiant de patient fictif à faire effacer.
#
# Usage (depuis adm01) :
#   ressources/E13-effacement/pousser-essai.sh [URL_LOKI]
#   URL_LOKI : par défaut WB_LOKI_URL ou http://loki.apps.par1.medisphere.internal:3100
#
# Aucune donnée réelle : l'identifiant « PAT-E13-0042 » et les noms sont inventés pour l'exercice.
# Le flux porte les étiquettes {job="essai-effacement", namespace="wb-essais"} (liste fermée du M22).
set -euo pipefail

url="${1:-${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}}"
command -v curl >/dev/null || { echo "curl manquant" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq manquant" >&2; exit 2; }

maintenant=$(date +%s%N)
lignes=(
  "rdv créé praticien=dr-morel creneau=09:00 statut=ok"
  "rdv créé praticien=dr-morel creneau=09:30 patient=PAT-E13-0042 statut=ok"
  "rdv annulé praticien=dr-benali creneau=10:00 statut=ok"
  "export agenda patient=PAT-E13-0042 nom=Jeanne-Exemple statut=erreur"
  "rdv créé praticien=dr-benali creneau=11:00 statut=ok"
)

# Corps JSON de l'API de poussée : horodatages en nanosecondes, chaînes de caractères.
corps=$(
  for i in "${!lignes[@]}"; do
    printf '%s\t%s\n' "$((maintenant + i * 1000000))" "${lignes[$i]}"
  done | jq -Rn '{streams: [{stream: {job: "essai-effacement", namespace: "wb-essais"},
                   values: [inputs | split("\t") | [.[0], .[1]]]}]}'
)

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -H 'Content-Type: application/json' -H 'X-Scope-OrgID: essai' \
  --data-binary "$corps" "$url/loki/api/v1/push") || code=000

if [[ "$code" == 204 ]]; then
  echo "5 lignes poussées dans le locataire essai ({job=\"essai-effacement\"}), dont 2 avec PAT-E13-0042."
  echo "Horodatage de la première ligne : $(date -d "@$((maintenant / 1000000000))" -Is)"
else
  echo "Échec de la poussée (HTTP $code) : Loki est-il joignable depuis adm01 sur $url ?" >&2
  exit 1
fi
