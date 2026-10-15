# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres et commandes distantes entre apostrophes
#
# check-E27.sh — M14-E27 « Auditer l'API »
# À lancer depuis adm01. Lecture seule : options des serveurs d'API (pods statiques), ConfigMap
# kubeadm-config, journaux d'audit des nœuds de contrôle lus par sudo -n et RÉDUITS SUR LE NŒUD à des
# décomptes (aucune ligne de journal ne quitte le nœud), dépôts GitLab.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E27 — Auditer l'API"
require_cmd kubectl jq ssh
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_M14_E27_POL=/etc/kubernetes/audit/politique.yaml
_M14_E27_LOG=/var/log/kubernetes/audit/audit.log

title "Serveurs d'API"
for _m14_e27_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e27_n : --audit-policy-file=$_M14_E27_POL" _m14p_arg_api "$_m14_e27_n" audit-policy-file "$_M14_E27_POL"
  check_cmd "$_m14_e27_n : --audit-log-path=$_M14_E27_LOG" _m14p_arg_api "$_m14_e27_n" audit-log-path "$_M14_E27_LOG"
  for _m14_e27_o in audit-log-maxage audit-log-maxbackup audit-log-maxsize; do
    check_cmd "$_m14_e27_n : --$_m14_e27_o borné (entier > 0)" _m14p_arg_api "$_m14_e27_n" "$_m14_e27_o" '[1-9][0-9]*'
  done
  check_cmd "$_m14_e27_n : serveur d'API prêt" _m14p_pod_pret "$(_m14p_pod_statique kube-apiserver "$_m14_e27_n")"
done
_m14_e27_cc="$(_m14p_cc || true)"
check_output "kubeadm-config contient les options d'audit (survivront à la prochaine montée)" '^ok$' \
  bash -c 'grep -q "audit-policy-file" <<<"$1" && grep -q "audit-log-maxbackup" <<<"$1" && echo ok' _ "$_m14_e27_cc"
check_cmd "plateforme/k8s : options d'audit dans cluster/kubeadm-config.yaml sur main" \
  _m14p_fichier_contient plateforme/k8s cluster/kubeadm-config.yaml 'audit-policy-file' 'audit-log-maxsize' 'extraVolumes'

title "Journaux d'audit"
# Sur le nœud, sortie réduite à « RECENT REQRECU SECRETS SECRETS_HORS_METADATA SECRETS_AVEC_CORPS SUPPRESSION ».
_M14_E27_BILAN='
d=/var/log/kubernetes/audit
recent=$(find "$d/audit.log" -mmin -10 2>/dev/null | grep -c .)
tout() { zcat -f "$d"/audit*.log* 2>/dev/null; }
rr=$(tail -n 20000 "$d/audit.log" 2>/dev/null | grep -c "\"stage\":\"RequestReceived\"")
sec=$(tout | grep "\"resource\":\"secrets\"")
nsec=$(grep -c . <<<"$sec")
hors=$(grep -vc "\"level\":\"Metadata\"" <<<"$sec")
corps=$(grep -Ec "\"(requestObject|responseObject)\"" <<<"$sec")
sup=$(tout | grep "\"verb\":\"delete\"" | grep "\"resource\":\"deployments\"" | grep "\"namespace\":\"mediagenda-dev\"" | grep -c "\"name\":\"rdv-essai-audit\"")
echo "$recent $rr $nsec $hors $corps $sup"'
_m14_e27_suppressions=0
for _m14_e27_n in "${_M14P_CP[@]}"; do
  check_ssh_output "$_m14_e27_n : politique d'audit présente (root, illisible des autres comptes)" "$_m14_e27_n" '^root [0-7][0-7]0$' \
    "sudo -n stat -c '%U %a' $_M14_E27_POL"
  read -r _m14_e27_recent _m14_e27_rr _m14_e27_nsec _m14_e27_hors _m14_e27_corps _m14_e27_sup \
    <<<"$(remote "$_m14_e27_n" "sudo -n bash -c '$_M14_E27_BILAN'" 2>/dev/null || echo "x x x x x x")"
  check_output "$_m14_e27_n : journal écrit dans les 10 dernières minutes" '^1$' echo "$_m14_e27_recent"
  check_output "$_m14_e27_n : aucune étape RequestReceived (20 000 derniers événements)" '^0$' echo "$_m14_e27_rr"
  check_output "$_m14_e27_n : Secrets audités uniquement en Metadata" '^ok$' \
    bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 && $2 == 0 )) && echo ok' _ "$_m14_e27_nsec" "$_m14_e27_hors"
  check_output "$_m14_e27_n : aucun corps de requête ou de réponse pour les Secrets" '^0$' echo "$_m14_e27_corps"
  if [[ "$_m14_e27_sup" =~ ^[0-9]+$ ]]; then _m14_e27_suppressions=$((_m14_e27_suppressions + _m14_e27_sup)); fi
done
check_output "la suppression de mediagenda-dev/rdv-essai-audit figure dans un des trois journaux" '^ok$' \
  bash -c '(( $1 >= 1 )) && echo ok' _ "$_m14_e27_suppressions"

title "Code et documentation"
check_cmd "plateforme/ansible : politique d'audit du rôle k8s_audit sur main (Secrets en Metadata)" \
  _m14p_fichier_contient plateforme/ansible roles/k8s_audit/files/politique.yaml 'kind: Policy' 'secrets' 'Metadata'
check_cmd "compte rendu d'enquête sur main (qui, quand, depuis où)" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/tests/enquete-audit.md 'rdv-essai-audit' 'sourceIPs|adresse'
