# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E25.sh — M26-E25 « Kubelets : certificats de service et approbation des CSR »
# À lancer depuis adm01. Lecture seule : Deployment et configuration de kubelet-csr-approver, demandes
# de certificat (CSR), ServiceMonitor du kubelet de kps et cibles dans Thanos Query, ConfigMap
# kubelet-config, fichier de configuration du kubelet de chaque nœud (SSH, sudo -n grep), journaux
# de l'approbateur (Loki, locataire plateforme), runbook sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E25 — Kubelets : certificats de service et approbation des CSR"
require_cmd kubectl jq curl ssh

title "Approbateur kubelet-csr-approver"
_m26_e25_ns=kubelet-csr-approver
check_cmd "Deployment kubelet-csr-approver : 2 réplicas prêts" _m26p_pret "$_m26_e25_ns" deployment kubelet-csr-approver 2
_m26_e25_dep="$(_m26p_json -n "$_m26_e25_ns" get deployment kubelet-csr-approver)"
check_cmd "image tirée par Harbor, version 1.2.x" _m26p_jq "$_m26_e25_dep" \
  'any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.+kubelet-csr-approver:v1\\.2\\."))'
_m26_e25_env() {
  jq -r --arg n "$1" '[.spec.template.spec.containers[].env[]? | select(.name == $n) | .value][0] // empty' <<<"$_m26_e25_dep" 2>/dev/null || true
}
check_output "noms acceptés : seulement k8s-cp0N et k8s-w0N (PROVIDER_REGEX)" '^\^k8s-\((cp\|w|w\|cp)\)0\[1-9\]\$$' \
  _m26_e25_env PROVIDER_REGEX
check_output "adresses acceptées : seulement le VLAN 40 (PROVIDER_IP_PREFIXES)" '^10\.10\.40\.0/24$' \
  _m26_e25_env PROVIDER_IP_PREFIXES
check_output "durée maximale acceptée : un an au plus (MAX_EXPIRATION_SEC)" '^(3[0-1][0-9]{6}|[1-2]?[0-9]{1,7})$' \
  _m26_e25_env MAX_EXPIRATION_SEC

title "Demandes de certificat de service"
_m26_e25_csr="$(_m26p_json get csr)"
if [[ "$_m26_e25_csr" == null ]]; then
  skip "demandes de certificat (CSR)" "lecture des CSR non permise au compte wb-checks"
else
  check_cmd "aucune demande kubelet-serving sans décision depuis plus de 15 minutes" _m26p_jq "$_m26_e25_csr" \
    '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving")
      | select((.status.conditions // []) | length == 0)
      | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 900)] | length == 0'
  # Les CSR traitées sont supprimées au bout d'une heure par le gestionnaire de contrôleurs.
  if _m26p_jq "$_m26_e25_csr" 'any(.items[]; .spec.signerName == "kubernetes.io/kubelet-serving" and (.spec.username | startswith("system:node:")) and ((.status.conditions // []) | length > 0))'; then
    check_cmd "la dernière demande d'un kubelet a été approuvée en moins de 5 minutes" _m26p_jq "$_m26_e25_csr" \
      '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving" and (.spec.username | startswith("system:node:")))
        | select((.status.conditions // []) | length > 0)] | sort_by(.metadata.creationTimestamp) | last
        | any(.status.conditions[]; .type == "Approved"
              and ((.lastUpdateTime | fromdateiso8601) - ($c | fromdateiso8601)) < 300)' \
      --arg c "$(jq -r '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving" and (.spec.username | startswith("system:node:")) and ((.status.conditions // []) | length > 0))] | sort_by(.metadata.creationTimestamp) | last | .metadata.creationTimestamp' <<<"$_m26_e25_csr")"
  else
    skip "délai d'approbation d'une demande réelle" "aucune demande traitée depuis une heure : provoque-en une (étape 3) puis relance"
  fi
fi
check_cmd "une demande forgée a été refusée par l'approbateur (journaux, 30 derniers jours)" \
  _m26p_loki_trouve '{namespace="kubelet-csr-approver"} |~ "(?i)deni|denied|refus"' plateforme 720h

title "Vérification TLS des kubelets par Prometheus"
_m26_e25_sm="$(_m26p_json -n supervision get servicemonitor kps-kubelet)"
check_cmd "ServiceMonitor kps-kubelet : vérification active (pas d'insecureSkipVerify), CA du cluster" _m26p_jq "$_m26_e25_sm" \
  '[.spec.endpoints[] | select(.scheme == "https")] | length > 0 and
   all(.[]; ((.tlsConfig.insecureSkipVerify // false) | not) and (.tlsConfig.ca.configMap.name // "") == "kube-root-ca.crt")'
_m26_e25_up="$(_m26p_valeur 'count(up{job="kubelet"} == 1)')"
check_cmd "cibles du kubelet up dans Prometheus (${_m26_e25_up:-0})" _m26p_compare "${_m26_e25_up:-0}" '>=' 6
check_output "aucune cible du kubelet en échec (certificat refusé ?)" '^0$' _m26p_nb 'up{job="kubelet"} == 0'

title "seccomp par défaut"
check_output "ConfigMap kubelet-config : seccompDefault: true" 'seccompDefault: *true' \
  kube -n kube-system get configmap kubelet-config -o 'jsonpath={.data.kubelet}'
for _m26_e25_n in "${_M26P_NOEUDS[@]}"; do
  check_ssh "$_m26_e25_n : seccompDefault: true dans /var/lib/kubelet/config.yaml" "$_m26_e25_n" \
    'sudo -n grep -Eq "^seccompDefault: *true" /var/lib/kubelet/config.yaml'
done
_m26_e25_crash="$(_m26p_json get pods -A)"
check_cmd "aucun pod en CrashLoopBackOff dans le cluster" _m26p_jq "$_m26_e25_crash" \
  '[.items[].status.containerStatuses[]? | select(.state.waiting.reason == "CrashLoopBackOff")] | length == 0'

title "Runbook"
check_cmd "$_M26P_DOC : RB-143 mentionne l'approbation automatique (kubelet-csr-approver)" \
  _m26p_doc_present "$_M26P_DOC" docs/kubernetes/runbooks 'RB-143' 20 'kubelet-csr-approver'
