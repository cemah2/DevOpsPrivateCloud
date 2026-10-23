# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions régulières entre apostrophes
#
# check-E38.sh — M24-E38 « Panne : jeton expiré à la première connexion » : idp01 et les nœuds de
# contrôle sont à l'heure (moins de 5 s d'adm01) et synchronisés par leur service de temps ; le jeton
# d'accès du royaume vit 5 minutes ; une alerte chargée surveille l'horloge des machines ; RB-246 ;
# journal ; panne close.
# Lecture seule : SSH admin (date, timedatectl show), keycloak_api (wb-checks, réglages du royaume),
# règles chargées par Prometheus, GitLab.

# shellcheck source=_m24-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert.sh"

title "M24-E38 — Horloges et durées des jetons justes"
require_cmd jq curl ssh

for _m24x_e38_h in "$_M24D_IDP" "${_M24X_CP[@]}"; do
  check_cmd "$_m24x_e38_h : à moins de 5 s d'adm01 et synchronisé par son service de temps (timedatectl)" \
    _m24x_a_l_heure "$_m24x_e38_h"
done
check_output "Royaume medisphere : jeton d'accès (et ID token) de 5 minutes (accessTokenLifespan = 300)" '^300$' \
  bash -c 'jq -r ".accessTokenLifespan // empty" <<<"$1"' _ "$(_m24p_royaume)"
# Les règles par défaut de kube-prometheus-stack (NodeClockSkewDetected, NodeClockNotSynchronising) ne
# visent que job="node-exporter" (nœuds du cluster) : elles ne comptent pas, idp01 n'y est pas.
_m24x_e38_alerte_temps() {
  prom_api "rules?type=alert" 2>/dev/null | jq -e '[.data.groups[]?.rules[]? | .query
    | select(test("node_time_seconds") or (test("node_timex_sync_status") and (test("job=\"node-exporter\"") | not)))]
    | length > 0' >/dev/null 2>&1
}
check_cmd "Prometheus : une alerte chargée (hors règles par défaut des nœuds) surveille l'horloge des VMs aussi" \
  _m24x_e38_alerte_temps
check_cmd "RB-246 sur main : section « jeton expiré dès l'émission »" _m24x_section "$(_m24x_rb246)" 'expir|horloge'
check_cmd "Journal de diagnostic M24-E38 sur main (docs/socle/journal/)" _m24x_journal E38
check_cmd "Panne M24-E38 close (lab/bin/break 24 38 --annuler après réparation)" _m24x_panne_close E38
