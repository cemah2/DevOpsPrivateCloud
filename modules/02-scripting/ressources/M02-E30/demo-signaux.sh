#!/usr/bin/env bash
# demo-signaux.sh — observer les signaux, les traps et les sous-processus en Bash (M02-E30).
#
# Usage : ./demo-signaux.sh premier-plan     (l'attente « sleep 120 » est au premier plan)
#         ./demo-signaux.sh arriere-plan     (sleep 120 & wait $!)
#         ./demo-signaux.sh arriere-plan-propre
#
# Pendant l'attente, essaie depuis un AUTRE terminal :  kill -TERM <PID affiché>
# puis, dans le terminal du script :                     Ctrl-C
# et observe à chaque fois : quand le trap s'exécute, et si un « sleep 120 » survit
# (pgrep -a sleep).
set -u

mode="${1:-premier-plan}"
enfant=""

nettoyer_enfant() {
  if [[ "$mode" == arriere-plan-propre && -n "$enfant" ]]; then
    kill -TERM "$enfant" 2>/dev/null && echo "[$$] enfant $enfant tué"
  fi
}
trap 'echo "[$$] $(date +%T) trap TERM"; nettoyer_enfant; exit 143' TERM
trap 'echo "[$$] $(date +%T) trap INT"; nettoyer_enfant; exit 130' INT
trap 'echo "[$$] $(date +%T) trap EXIT (nettoyage final)"' EXIT

echo "[$$] $(date +%T) démarrage, mode $mode, groupe de processus $(ps -o pgid= -p $$ | tr -d ' ')"
case "$mode" in
  premier-plan)
    sleep 120
    ;;
  arriere-plan | arriere-plan-propre)
    sleep 120 &
    enfant=$!
    echo "[$$] enfant sleep : PID $enfant"
    wait "$enfant"
    ;;
  *)
    echo "mode inconnu : $mode" >&2
    exit 2
    ;;
esac
echo "[$$] $(date +%T) fin normale"
