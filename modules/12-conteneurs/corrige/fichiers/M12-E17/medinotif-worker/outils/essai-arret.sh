#!/usr/bin/env bash
# outils/essai-arret.sh — mesure l'arrêt propre du worker (M12-E17, ctr01).
# Publie un message, attend que le worker le prenne, arrête le conteneur pendant l'envoi simulé
# (3 s), puis affiche la durée de l'arrêt, le code de sortie et les dernières lignes du journal.
set -euo pipefail
cd "$(dirname "$0")/.."
projet=medinotif
ctr_rmq="$(docker compose -p "$projet" ps -q rabbitmq)"
ctr_wrk="$(docker compose -p "$projet" ps -q worker)"
[[ -n "$ctr_rmq" && -n "$ctr_wrk" ]] || { echo "pile medinotif absente : docker compose up -d --wait" >&2; exit 1; }
message='{"type":"sms","destinataire":"+33612345678","modele":"rappel-veille","rendez_vous_id":42}'
# Publication par pika, la bibliothèque AMQP déjà présente dans l'image du worker (l'image
# rabbitmq:4.1 n'a pas rabbitmqadmin).
docker exec -i "$ctr_wrk" python - "$message" <<'PY'
import os, sys, pika
mdp = open("/run/secrets/amqp_mdp").read().strip()
cnx = pika.BlockingConnection(pika.URLParameters(f"amqp://medinotif:{mdp}@rabbitmq:5672/%2F"))
cnx.channel().basic_publish(exchange="", routing_key="notifications", body=sys.argv[1].encode())
cnx.close()
PY
sleep 1   # le worker a pris le message ; l'envoi simulé dure 3 s
debut=$(date +%s.%N)
docker stop "$ctr_wrk" >/dev/null
fin=$(date +%s.%N)
printf 'durée de l arrêt : %s s ; code de sortie : %s\n' "$(awk -v d="$debut" -v f="$fin" 'BEGIN { printf "%.1f", f - d }')" \
  "$(docker inspect -f '{{.State.ExitCode}}' "$ctr_wrk")"
docker logs --tail 4 "$ctr_wrk"
docker start "$ctr_wrk" >/dev/null
