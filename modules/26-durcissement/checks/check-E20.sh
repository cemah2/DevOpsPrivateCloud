# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E20.sh — M26-E20 : Tetragon, observer processus, fichiers et réseau
# À lancer depuis adm01. Lecture seule : DaemonSet et TracingPolicy (compte wb-checks, wb-checks-securite
# étendue en E20), Prometheus, Loki (locataires audit et plateforme), dépôt (GitLab).
# Ce qui est vérifié : Tetragon en service partout ; les trois politiques chargées, sans action de
# blocage ; métriques collectées ; événements dans le locataire audit (dont un essai observer-exec) et
# plus dans le locataire plateforme ; les requêtes de corrélation versionnées.

# shellcheck source=_m26-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel-c.sh"

title "M26-E20 — Tetragon : observer processus, fichiers et réseau"
require_cmd jq kubectl curl

check_cmd "DaemonSet tetragon prêt sur les $_M26C_NOEUDS nœuds" _m26c_ds_pret tetragon tetragon

_m26c_e20_tp="$(_m26c_k get tracingpolicies.cilium.io -o json)"
if [[ -z "$_m26c_e20_tp" ]]; then
  check_cmd "TracingPolicy lisibles par le compte des vérifications (wb-checks-securite étendue)" false
else
  for _m26c_e20_p in observer-exec fichiers-sensibles connexions-sortantes; do
    check_cmd "TracingPolicy $_m26c_e20_p présente" \
      _m26c_json "$_m26c_e20_tp" --arg n "$_m26c_e20_p" 'any(.items[]; .metadata.name == $n)'
  done
  check_cmd "aucune de ces politiques ne bloque (pas de Sigkill, Override ni Signal à ce stade)" \
    _m26c_json "$_m26c_e20_tp" '[.items[] | select(.metadata.name | test("^(observer-exec|fichiers-sensibles|connexions-sortantes)$"))] as $tp
      | ($tp | length) == 3
      and ([$tp[] | .. | objects | select(has("action")) | .action] | all(. != "Sigkill" and . != "Override" and . != "Signal"))'
fi

check_cmd "Prometheus collecte les métriques de Tetragon (tetragon_events_total)" \
  _m26c_prom_existe 'count(tetragon_events_total) > 0'

check_cmd "Loki (audit) : événements service=\"tetragon\" dans la dernière heure" \
  _m26c_loki_present '{service="tetragon"}' audit 1h
check_cmd "Loki (audit) : un événement de la politique observer-exec dans les 7 derniers jours (essai de l'étape 6)" \
  _m26c_loki_present '{service="tetragon"} |= "observer-exec"' audit 168h
check_cmd "Loki (plateforme) : plus aucune ligne de tetragon/export-stdout dans la dernière heure" \
  _m26c_loki_absent '{namespace="tetragon", container="export-stdout"}' plateforme 1h

check_cmd "plateforme/observabilite : requetes/tetragon-falco.logql sur main" \
  _m26c_fichier "$_M26C_P_OBS" requetes/tetragon-falco.logql
