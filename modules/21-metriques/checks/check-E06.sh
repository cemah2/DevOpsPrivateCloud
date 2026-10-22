# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E06.sh — M21-E06 : Alertmanager : routes, regroupement et courriels
# À lancer depuis adm01. Lecture seule : API v2 d'Alertmanager (10.10.41.61), API de Mailpit
# (compte des checks), « kube » pour la ConfigMap de la racine.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E06 — Alertmanager : routes, regroupement et courriels"
require_cmd jq curl

_m21d_e06_statut="$(am_api status 2>/dev/null || true)"
if [[ -z "$_m21d_e06_statut" ]]; then
  _ko "Alertmanager ne répond pas sur http://alertmanager.apps.par1.medisphere.internal:9093 (M21-E02)"
  return 0
fi
# Configuration effective (celle qu'Alertmanager a chargée, pas celle du dépôt), en JSON.
_m21d_e06_conf="$(jq -r '.config.original // empty' <<<"$_m21d_e06_statut" | _m21d_yaml_json)"
if [[ -z "$_m21d_e06_conf" ]]; then
  skip "Lecture de la configuration chargée" "aucun convertisseur YAML sur adm01 (yq ou python3-yaml) : installe-en un"
  return 0
fi

check_cmd "SMTP : smtp.par1.medisphere.internal:25, STARTTLS exigé, expéditeur @medisphere.internal" _m21d_json "$_m21d_e06_conf" \
  '.global.smtp_smarthost == "smtp.par1.medisphere.internal:25" and .global.smtp_require_tls == true
   and (.global.smtp_from | test("@medisphere\\.internal$"))'
check_cmd "SMTP : certificat de Mailpit vérifié par un fichier de CA (pas insecure_skip_verify)" _m21d_json "$_m21d_e06_conf" \
  '(.global.smtp_tls_config.ca_file // "" | length > 0) and (.global.smtp_tls_config.insecure_skip_verify // false | not)'
check_cmd "Récepteurs plateforme-mail, astreinte-mail, mediagenda-mail, medidoc-mail (adresses @medisphere.internal)" \
  _m21d_json "$_m21d_e06_conf" \
  '[.receivers[] | select(.name | IN("plateforme-mail","astreinte-mail","mediagenda-mail","medidoc-mail"))
    | select(([.email_configs[]?.to] | length) >= 1 and all(.email_configs[]; .to | test("@medisphere\\.internal$")))]
   | length == 4'
check_cmd "Route racine : récepteur par défaut plateforme-mail, regroupement par alertname et namespace" _m21d_json "$_m21d_e06_conf" \
  '.route.receiver == "plateforme-mail" and ((.route.group_by // []) | index("alertname") != null and index("namespace") != null)'
check_cmd "Délais de regroupement choisis (group_wait ≤ 1 min, group_interval ≥ 1 min, repeat_interval ≥ 1 h)" _m21d_json "$_m21d_e06_conf" \
  'def s: if . == null then null else capture("^(?<n>[0-9]+)(?<u>ms|s|m|h|d)$") as $c
           | ($c.n | tonumber) * ({"ms":0.001,"s":1,"m":60,"h":3600,"d":86400}[$c.u]) end;
   (.route.group_wait | s) <= 60 and (.route.group_interval | s) >= 60 and (.route.repeat_interval | s) >= 3600'
check_cmd "Watchdog ne part jamais par courriel (route vers un récepteur sans notification)" _m21d_json "$_m21d_e06_conf" \
  '. as $c | [.route.routes[]? | select((.matchers // []) | any(test("alertname *= *\"?Watchdog")))] | length >= 1
   and all(.[]; .receiver as $r | [$c.receivers[] | select(.name == $r) | (.email_configs // []) | length] | add == 0)'
check_cmd "Les alertes critiques (gravite=critique) vont à l'astreinte" _m21d_json "$_m21d_e06_conf" \
  '[.route.routes[]? | select((.matchers // []) | any(test("gravite *= *\"?critique")))] | .[0].receiver == "astreinte-mail"'
check_cmd "ConfigMap racine-medisphere (ca.crt) dans supervision, montée dans Alertmanager" bash -c \
  'jq -e ".data[\"ca.crt\"] | test(\"BEGIN CERTIFICATE\")" <<<"$1" >/dev/null &&
   jq -e "[.items[] | select(.metadata.name == \"kps\") | .spec.configMaps[]?] | index(\"racine-medisphere\") != null" <<<"$2" >/dev/null' _ \
  "$(_m21d_k -n "$_M21D_NS" get configmap racine-medisphere -o json)" \
  "$(_m21d_k -n "$_M21D_NS" get alertmanagers.monitoring.coreos.com -o json)"

# --- Le courriel de l'alerte d'essai ------------------------------------------------------------------
_m21d_e06_mails="$(mailpit_api "search?query=$(_m21d_uri 'subject:EssaiPLAT2206')" 2>/dev/null || true)"
check_cmd "Mailpit : courriel de l'alerte d'essai EssaiPLAT2206 reçu par plateforme@medisphere.internal" _m21d_json "$_m21d_e06_mails" \
  '[.messages[]? | select([.To[]?.Address] | index("plateforme@medisphere.internal"))] | length >= 1'
check_cmd "Mailpit : l'alerte d'essai a aussi été notifiée résolue (send_resolved)" _m21d_json "$_m21d_e06_mails" \
  '[.messages[]? | select(.Subject | test("RESOLVED"; "i"))] | length >= 1'
check_cmd "Mailpit : l'alerte critique d'essai EssaiCritiquePLAT2206 a atteint astreinte@medisphere.internal" bash -c \
  'jq -e "[.messages[]? | select([.To[]?.Address] | index(\"astreinte@medisphere.internal\"))] | length >= 1" <<<"$1" >/dev/null' _ \
  "$(mailpit_api "search?query=$(_m21d_uri 'subject:EssaiCritiquePLAT2206')" 2>/dev/null || true)"
