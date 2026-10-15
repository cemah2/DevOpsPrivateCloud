# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E19.sh — M17-E19 « Panne : la release est bloquée » : releases du dev et de metrics-server
# « deployed », aucune release en attente, aucun Secret de révision illisible ou orphelin, services
# rendus, RB-170 publié. Lecture seule (Secrets de release lus avec le kubeconfig personnel).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E19 — Release bloquée"
require_cmd jq kubectl helm

# _e19_coherente ESPACE RELEASE — la plus haute révision lue par Helm est la plus haute des Secrets.
_e19_coherente() {
  local h s
  h="$(_m17p_helm history "$2" -n "$1" --max 100 -o json | jq '[.[].revision] | max // 0' 2>/dev/null)" || h=0
  s="$(_m17p_kadmin get secret -n "$1" -l "owner=helm,name=$2" -o json | jq '[.items[].metadata.labels.version | tonumber] | max // 0' 2>/dev/null)" || s=-1
  [[ "$h" =~ ^[0-9]+$ && "$s" =~ ^[0-9]+$ ]] && ((h > 0 && h == s))
}

for _e19_c in "mediagenda-dev mediagenda" "kube-system metrics-server"; do
  read -r _e19_ns _e19_r <<<"$_e19_c"
  check_output "$_e19_ns/$_e19_r : deployed" '^deployed$' _m17p_rel_statut "$_e19_ns" "$_e19_r"
  check_cmd "$_e19_ns/$_e19_r : historique lisible jusqu'à la dernière révision stockée" _e19_coherente "$_e19_ns" "$_e19_r"
done
_e19_attente() { [[ -z "$(_m17p_helm list -A --pending -q)" ]]; }
check_cmd "aucune release du cluster en état pending-*" _e19_attente

_e19_d="$(_m17p_deploy mediagenda-dev mediagenda)" || _e19_d=""
check_cmd "dev : Deployment mediagenda à jour, pods prêts" _m17p_deploy_a_jour "$_e19_d"
check_output "API de métriques (v1beta1.metrics.k8s.io) disponible" '^True$' \
  kube get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
check_cmd "plateforme/medisphere : RB-170 publié (docs/kubernetes/packaging/runbooks/)" \
  bash -c "grep -q 'RB-170' <<<\"\$1\"" _ "$(_m17p_gl_arbre plateforme/medisphere docs/kubernetes/packaging/runbooks)"
check_cmd "panne M17-E19 close (lab/bin/break 17 19 --annuler après réparation)" _m17p_panne_close E19
