#!/bin/sh
# Production d'un lot d'essai sur Kafka (M27-E09, E10). Lit le mot de passe dans SASL_JAAS (variable
# remplie par le Secret de l'utilisateur), jamais en argument. kafka-console-producer rend 0 même
# quand l'authentification échoue : on lit son journal d'erreurs.
set -eu
umask 077
cat > /tmp/client.properties <<FIN
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=${SASL_JAAS}
ssl.truststore.type=PEM
ssl.truststore.location=/ca/ca.crt
FIN
debut=$(date +%s)
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "$AMORCE" --topic "$TOPIC" \
  --command-config /tmp/client.properties --command-property acks=all \
  < /messages/messages.jsonl 2> /tmp/erreurs.log
fin=$(date +%s)
if grep -q 'ERROR' /tmp/erreurs.log; then
  grep 'ERROR' /tmp/erreurs.log | head -5 >&2
  echo "ÉCHEC : des messages n'ont pas été acceptés (voir ci-dessus)" >&2
  exit 1
fi
echo "lot envoyé : $(wc -l < /messages/messages.jsonl) messages en $((fin - debut)) s (acks=all), fin à $(date -u +%H:%M:%S) UTC"
