#!/usr/bin/env bash
# surveiller-ci-jobs.sh — garde l'état final de chaque pod de job de ci-jobs (M19-E42), depuis adm01.
# Les pods de job sont supprimés à la fin du job : ce script enregistre leur JSON complet dès qu'ils
# passent en Failed (ou disparaissent après avoir été vus), et les événements de l'espace.
# Usage : surveiller-ci-jobs.sh [DOSSIER]   (Ctrl+C pour arrêter ; lecture seule sur le cluster)
set -euo pipefail

DOSSIER="${1:-$HOME/m19/e42/$(date +%Y%m%d-%H%M%S)}"
NS="${NS:-ci-jobs}"
mkdir -p "$DOSSIER"
chmod 700 "$DOSSIER"
echo "Enregistrement dans $DOSSIER (espace $NS)…"

kubectl -n "$NS" get events -w -o json | jq -c --unbuffered "." >"$DOSSIER/evenements.jsonl" &
pid_ev=$!
trap 'kill "$pid_ev" 2>/dev/null || true; echo; echo "Fichiers : $DOSSIER"' EXIT

kubectl -n "$NS" get pods -w -o json | jq -c --unbuffered '.' | while read -r p; do
  nom="$(jq -r '.metadata.name' <<<"$p")"
  phase="$(jq -r '.status.phase // ""' <<<"$p")"
  printf '%s %-60s %s %s\n' "$(date +%T)" "$nom" "$phase" "$(jq -r '.status.reason // ""' <<<"$p")"
  # Dernier état connu de chaque pod (écrasé à chaque changement : on garde le plus récent).
  printf '%s\n' "$p" >"$DOSSIER/$nom.json"
  if [[ "$phase" == Failed ]]; then
    jq '{nom: .metadata.name, raison: .status.reason, message: .status.message, delai: .spec.activeDeadlineSeconds,
         priorite: .spec.priorityClassName, conteneurs: [.status.containerStatuses[]? | {name, state, lastState}],
         ressources: [.spec.containers[] | {name, resources}]}' <<<"$p" >"$DOSSIER/$nom.echec.json"
  fi
done
