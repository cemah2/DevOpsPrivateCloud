# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E26.sh — M15-E26 « Superviser le réseau du cluster »
# Lecture seule : métriques HTTP des agents et de Hubble, objets du cluster (wb-checks), unités systemd
# et une exécution de la sonde (qui ne fait que lire), fichiers de plateforme/outils et plateforme/k8s
# (API GitLab), requêtes HTTPS vers hubble.apps (gw-par1) et vers la VIP des répartiteurs.

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E26 — Superviser le réseau du cluster"
require_cmd kubectl jq yq curl systemctl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Métriques"
for _m15_e26_n in "${_M15P_WORKERS[@]}"; do
  _m15_e26_ip="$(_m15p_ip_noeud "$_m15_e26_n")"
  check_output "$_m15_e26_n : métriques de l'agent sur 9962" '^cilium_' \
    curl -s --max-time "$WB_TIMEOUT" "http://${_m15_e26_ip:-0.0.0.0}:9962/metrics"
  check_output "$_m15_e26_n : métriques de Hubble sur 9965" '^hubble_flows_processed_total' \
    curl -s --max-time "$WB_TIMEOUT" "http://${_m15_e26_ip:-0.0.0.0}:9965/metrics"
done
check_cmd "values sur main : métriques de l'agent, familles Hubble et Hubble UI déclarées" \
  _m15p_values_jq '.prometheus.enabled == true and (.hubble.metrics.enabled | length) > 0 and .hubble.ui.enabled == true'

title "La sonde ms-verif-k8s-reseau (adm01)"
_m15_e26_svc=ms-verif-k8s-reseau.service
_m15_e26_tim=ms-verif-k8s-reseau.timer
check_cmd "la sonde est installée sous /usr/local/bin" test -x /usr/local/bin/ms-verif-k8s-reseau
check_cmd "sa configuration est installée sous /usr/local/etc" test -r /usr/local/etc/ms-verif-k8s-reseau.conf
check_cmd "la sonde conclut que le réseau du cluster va bien (code 0)" timeout 180 /usr/local/bin/ms-verif-k8s-reseau --quiet
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-k8s-reseau --nimporte-quoi >/dev/null 2>&1; echo $?'
check_output "le service tourne en admin" '^User=admin$' systemctl show -p User "$_m15_e26_svc"
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' systemctl show -p OnFailure "$_m15_e26_svc"
check_cmd "le timer est activé et actif" bash -c "systemctl is-enabled --quiet $_m15_e26_tim && systemctl is-active --quiet $_m15_e26_tim"
check_output "le timer passe toutes les 5 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/5(:00)?' systemctl show -p TimersCalendar "$_m15_e26_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' systemctl show -p Persistent "$_m15_e26_tim"
check_output "la chaîne d'alerte a été testée (alerte ms-alerte sur ce service, 30 jours)" \
  "(ÉCHEC|ECHEC) $_m15_e26_svc" sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat
_m15_e26_bats() { [[ -n "$(_m15p_contenu_main plateforme/outils tests/bats/ms-verif-k8s-reseau.bats)" ]]; }
check_cmd "plateforme/outils : tests bats de la sonde sur main" _m15_e26_bats
check_cmd "plateforme/outils : un job bats a réussi sur main" _m15p_job_reussi plateforme/outils bats

title "Identité de la sonde"
_m15_e26_kc="$HOME/.config/workbook/k8s-supervision.kubeconfig"
check_cmd "le compte de service supervision/ms-supervision existe" \
  _m15p_jq "$(_m15p_get -n supervision serviceaccount ms-supervision)" '.metadata.name == "ms-supervision"'
check_cmd "kubeconfig de supervision en 600 ($_m15_e26_kc)" _m15p_mode_600 "$_m15_e26_kc"
check_output "ms-supervision lit les nœuds" '^yes$' kubectl --kubeconfig "$_m15_e26_kc" auth can-i list nodes
check_output "ms-supervision ne lit PAS les Secrets" '^no$' \
  bash -c 'kubectl --kubeconfig "$1" auth can-i get secrets -n kube-system 2>/dev/null || true' _ "$_m15_e26_kc"

title "Hubble UI"
_m15_e26_h="hubble.$_M15P_APPS"
check_cmd "https://$_m15_e26_h répond depuis adm01 (certificat valide)" _m15p_https_code "https://$_m15_e26_h/" '^(200|30[12])$'
check_cmd "le nom $_m15_e26_h résout vers $_M15P_GW_IP" _m15p_resout "$_m15_e26_h" "$_M15P_GW_IP"
_m15_e26_cnp() {
  _m15p_jq "$(_m15p_get -n kube-system ciliumnetworkpolicies)" \
    'any(.items[]; (.spec.endpointSelector.matchLabels // {} | to_entries | any((.key | test("k8s-app$")) and .value == "hubble-ui"))
       and (.spec.ingress | length) > 0
       and all(.spec.ingress[]; (.fromEntities // []) == ["ingress"] and ((.fromEndpoints // []) | length) == 0 and ((.fromCIDR // []) + (.fromCIDRSet // []) | length) == 0))'
}
check_cmd "une politique Cilium n'admet en entrée des pods hubble-ui que l'identité « ingress » (Gateway)" _m15_e26_cnp
_m15_e26_lb() {
  local c
  c="$(_m15p_code_https "https://$_m15_e26_h/" --resolve "$_m15_e26_h:443:10.10.70.200")"
  [[ ! "$c" =~ ^[23] ]]
}
check_cmd "$_m15_e26_h n'est PAS servi par la VIP des répartiteurs (10.10.70.200)" _m15_e26_lb
