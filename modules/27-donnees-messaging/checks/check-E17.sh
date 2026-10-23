# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E17.sh — M27-E17 « ADR : données et messagerie » (RED) : présence et contenu de l'ADR-0270 dans
# plateforme/medisphere. La qualité de l'argumentaire s'évalue avec le corrigé. Lecture seule.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

title "M27-E17 — ADR-0270 : données et messagerie"
require_cmd jq curl

check_cmd "ADR-0270 publié dans docs/donnees/adr/ (messagerie : RabbitMQ, Kafka, NATS)" \
  _m27p_doc "$_m27p_docs/adr" ADR-0270 'RabbitMQ' 'Kafka' 'NATS' 'quorum'
check_cmd "ADR-0270 : PostgreSQL (CloudNativePG contre Patroni, mesures)" \
  _m27p_doc "$_m27p_docs/adr" ADR-0270 'Patroni' 'CloudNativePG|CNPG' '[0-9]+([,.][0-9]+)? ?s\b'
check_cmd "ADR-0270 : migrations et licences (Flyway, Liquibase FSL, Atlas Community, Apache 2.0)" \
  _m27p_doc "$_m27p_docs/adr" ADR-0270 'Flyway' 'Liquibase' 'FSL' 'Atlas' 'Community' 'Apache'
check_cmd "ADR-0270 : outbox et idempotence, conditions de révision" \
  _m27p_doc "$_m27p_docs/adr" ADR-0270 'outbox' 'idempot' 'r[ée]vision'
