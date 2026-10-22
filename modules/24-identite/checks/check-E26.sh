# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E26.sh — M24-E26 : Superviser l'identité : santé, métriques, événements
# À lancer depuis adm01. Lecture seule : ScrapeConfig (kube), Prometheus (cible, métrique, règles),
# ruler et requêtes de Loki (locataires audit et plateforme), témoin de mon01, royaume medisphere
# (événements, wb-checks), tests des règles sur main.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E26 — Superviser l'identité : santé, métriques, événements"
require_cmd jq curl kubectl

# --- 1. Métriques et alertes ---------------------------------------------------------------------------
check_cmd "ScrapeConfig keycloak dans l'espace supervision" \
  kube -n supervision get scrapeconfigs.monitoring.coreos.com keycloak -o name
check_output "Prometheus : la cible keycloak (idp01:9000) est collectée (up == 1)" '^1$' \
  _m24p_valeur 'max(up{job="keycloak"})'
check_cmd "Prometheus : le compteur keycloak_user_events_total existe (métriques d'événements activées)" \
  _m24p_compare "$(_m24p_valeur 'count(keycloak_user_events_total)')" '>' 0
for _m24p_e26_a in KeycloakIndisponible KeycloakEchecsConnexion; do
  check_cmd "Prometheus : règle d'alerte $_m24p_e26_a chargée" _m24p_alerte_chargee "$_m24p_e26_a"
done
check_cmd "plateforme/observabilite : tests des règles d'identité sur main (tests/identite.test.yaml)" \
  _m24p_tous "$(_m24d_contenu_main plateforme/observabilite tests/identite.test.yaml)" 'KeycloakIndisponible' 'KeycloakEchecsConnexion'
check_cmd "Ruler de Loki (locataire audit) : FederationLdapEnEchec chargée" \
  _m24d_contient "$(_m24p_ruler audit)" '^FederationLdapEnEchec$'

# --- 2. Journaux d'audit -----------------------------------------------------------------------------------
check_cmd "Loki (audit) : journaux de Keycloak reçus dans la dernière heure (service=\"keycloak\")" \
  _m24p_compare "$(_m24p_loki_lignes '{service="keycloak"}' audit 1h)" '>' 0
check_cmd "Loki (audit) : journaux de FreeIPA reçus dans la dernière heure (service=\"freeipa\")" \
  _m24p_compare "$(_m24p_loki_lignes '{service="freeipa"}' audit 1h)" '>' 0
check_cmd "Loki (plateforme) : le journal d'idp01 arrive toujours (sshd, système)" \
  _m24p_compare "$(_m24p_loki_lignes '{job="journald", host="idp01"}' plateforme 6h)" '>' 0
check_cmd "Loki (plateforme) : plus aucune ligne de keycloak.service depuis 15 minutes (audit seulement)" \
  _m24p_compare "$(_m24p_loki_lignes '{job="journald", host="idp01"} | unite="keycloak.service"' plateforme 15m)" '==' 0

# --- 3. Témoin et événements du royaume ------------------------------------------------------------------
check_output "Témoin de mon01 : la sonde de sso réussit (probe_success == 1)" '^1$' \
  _m24p_temoin_valeur 'max(probe_success{instance=~"https://sso\\.par1\\.medisphere\\.internal/.*"})'
_m24p_e26_royaume="$(_m24p_royaume)"
check_cmd "Royaume medisphere : événements et événements d'administration (avec détails) stockés" _m24d_json \
  "$_m24p_e26_royaume" '.eventsEnabled == true and .adminEventsEnabled == true and .adminEventsDetailsEnabled == true'
check_cmd "plateforme/identite : événements décrits par OpenTofu (keycloak_realm_events)" \
  _m24d_contient "$(_m24p_tofu_tout)" 'resource +"keycloak_realm_events"'
