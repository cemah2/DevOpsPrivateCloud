# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E27.sh — M16-E27 « Superviser le stockage du cluster »
# Lecture seule : compte de service et ClusterRole de la sonde, sonde installée sur adm01 (lancée :
# elle ne fait que lire), timer, PVC de test, dépôt plateforme/outils (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E27 — Superviser le stockage du cluster"
require_cmd jq kubectl curl systemctl

title "Identité de la sonde"
check_cmd "compte de service wb-system/ms-supervision-stockage" \
  _m16p_jq "$(_m16p_kj serviceaccount ms-supervision-stockage -n wb-system)" '.metadata.name == "ms-supervision-stockage"'
_m16_e27_cr="$(_m16p_kj clusterrole ms-supervision-stockage)"
check_cmd "ClusterRole ms-supervision-stockage : lecture des métriques du kubelet (nodes/metrics)" \
  _m16p_jq "$_m16_e27_cr" 'any(.rules[]; (.resources // []) | index("nodes/metrics"))'
check_cmd "ClusterRole : ni Secrets, ni nodes/proxy, ni joker" \
  _m16p_jq "$_m16_e27_cr" '(.rules | length) > 0 and all(.rules[]; ((.resources // []) | map(. == "secrets" or . == "nodes/proxy" or . == "*") | any | not))'
check_cmd "ClusterRole : aucun verbe d'écriture" \
  _m16p_jq "$_m16_e27_cr" 'all(.rules[]; (.verbs // []) | all(. == "get" or . == "list" or . == "watch"))'
check_cmd "kubeconfig de la sonde présent, en 600" \
  bash -c '[[ "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]' _ "$HOME/.config/workbook/k8s-supervision-stockage.kubeconfig"

title "Sonde"
_m16_e27_s=/usr/local/bin/ms-verif-k8s-stockage
check_cmd "$_m16_e27_s installé et exécutable" test -x "$_m16_e27_s"
check_cmd "configuration /usr/local/etc/ms-verif-k8s-stockage.conf présente" test -r /usr/local/etc/ms-verif-k8s-stockage.conf
check_cmd "la sonde conclut que le stockage va bien (code 0)" timeout 240 "$_m16_e27_s" --quiet
check_cmd "une option inconnue donne le code 2" \
  bash -c '"$1" --option-inexistante >/dev/null 2>&1; [[ $? -eq 2 ]]' _ "$_m16_e27_s"
check_cmd "timer ms-verif-k8s-stockage.timer actif" systemctl is-active --quiet ms-verif-k8s-stockage.timer
check_output "timer : toutes les 10 minutes" '0/10' systemctl show ms-verif-k8s-stockage.timer -p TimersCalendar
check_output "service : OnFailure vers ms-alerte@" 'ms-alerte@' systemctl show ms-verif-k8s-stockage.service -p OnFailure
check_cmd "le PVC de test de l'alerte n'existe plus (aucun PVC Pending dans wb-essais)" \
  _m16p_jq "$(_m16p_kj pvc -n wb-essais)" 'all(.items[]?; .status.phase != "Pending")'

title "Code et documentation"
_m16_e27_bats() { _m16p_fichier_main plateforme/outils tests/bats/ms-verif-k8s-stockage.bats 2>/dev/null | grep -q '@test'; }
_m16_e27_astreinte() { _m16p_fichier_main plateforme/outils docs/astreinte.md 2>/dev/null | grep -qi 'stockage kubernetes'; }
check_cmd "plateforme/outils : tests bats de la sonde sur main" _m16_e27_bats
check_cmd "plateforme/outils : dernier pipeline de main réussi" _m16p_pipeline_ok plateforme/outils
check_cmd "plateforme/outils : docs/astreinte.md contient la section « Stockage Kubernetes »" _m16_e27_astreinte
