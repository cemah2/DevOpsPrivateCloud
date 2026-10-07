# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E34.sh — M04-E34 « Un rôle complet en temps limité » (rôle node_exporter)
# Structure du rôle et du scénario sur main, job Molecule réussi en CI, instance 2049 détruite.
# Le respect du temps (T4 − T0) et la grille du corrigé relèvent de l'auto-évaluation.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E34 — Rôle node_exporter en temps limité"
require_cmd jq ssh curl
_m04_charger

title "Rôle et scénario (branche main)"
for _m04_f in roles/node_exporter/tasks/main.yml roles/node_exporter/defaults/main.yml \
  roles/node_exporter/handlers/main.yml roles/node_exporter/meta/argument_specs.yml roles/node_exporter/README.md \
  molecule/node_exporter/molecule.yml molecule/node_exporter/converge.yml molecule/node_exporter/verify.yml \
  molecule/node_exporter/inventaire/hosts.yml; do
  check_cmd "$_m04_f présent sur main" _m04_fichier_main "$_m04_f"
done
check_cmd "le rôle installe le paquet Debian prometheus-node-exporter" \
  _m04_fichier_main_contient roles/node_exporter/tasks/main.yml 'prometheus-node-exporter'
check_cmd "le scénario utilise le VMID 2049" \
  _m04_fichier_main_contient molecule/node_exporter/inventaire/hosts.yml '2049'
check_cmd "verify.yml contrôle /metrics par HTTP" \
  _m04_fichier_main_contient molecule/node_exporter/verify.yml '/metrics'
check_cmd ".gitlab-ci.yml : job Molecule du rôle" \
  _m04_fichier_main_contient .gitlab-ci.yml 'SCENARIO:[[:space:]]*node_exporter'

title "Exécution"
check_cmd "le job molecule:node_exporter a réussi en CI" _m04_job_reussi '^molecule:node_exporter$'
check_cmd "instance 2049 détruite" _m04_aucune_vm 2049 2049
