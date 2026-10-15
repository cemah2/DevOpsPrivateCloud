# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M15-E39 « Panne : la Gateway refuse le HTTPS » : Gateway programmée, écouteurs aux
# références résolues, certificat dans l'espace de la Gateway, route acceptée, TLS valide de bout en
# bout. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E39 — La Gateway sert le HTTPS"
require_cmd kubectl jq curl

check_cmd "Gateway $_m15x_gw : Accepted et Programmed" \
  _m15x_jq '[.status.conditions[]? | select(.status == "True") | .type] | index("Accepted") != null and index("Programmed") != null' \
  -n "$_m15x_gw_ns" gateway "$_m15x_gw"
check_cmd "tous les écouteurs de $_m15x_gw ont ResolvedRefs et Programmed à True" \
  _m15x_jq '(.status.listeners | length > 0) and (.status.listeners | all([.conditions[]? | select(.status == "True") | .type] | index("ResolvedRefs") != null and index("Programmed") != null))' \
  -n "$_m15x_gw_ns" gateway "$_m15x_gw"
check_cmd "le certificat de l'écouteur HTTPS est dans l'espace $_m15x_gw_ns" \
  _m15x_jq "[.spec.listeners[] | select(.protocol == \"HTTPS\") | .tls.certificateRefs[]? | (.namespace // \"$_m15x_gw_ns\")] | length > 0 and all(. == \"$_m15x_gw_ns\")" \
  -n "$_m15x_gw_ns" gateway "$_m15x_gw"
check_cmd "l'espace $_m15x_ns_app porte medisphere.internal/exposition=oui" \
  _m15x_jq '.metadata.labels["medisphere.internal/exposition"] == "oui"' ns "$_m15x_ns_app"
check_cmd "route $_m15x_route acceptée par $_m15x_gw" _m15x_route_acceptee "$_m15x_ns_app" "$_m15x_route"
check_cmd "TLS vérifié (CA MédiSphère, nom $_m15x_hote) et réponse 200 sur /sante" _m15x_https_200 /sante
check_output "le port 80 redirige vers HTTPS" '^30[18]$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "http://$_m15x_hote/sante"
check_cmd "panne M15-E39 close (lab/bin/break 15 39 --annuler après réparation)" _m15x_aucune_panne_active E39
