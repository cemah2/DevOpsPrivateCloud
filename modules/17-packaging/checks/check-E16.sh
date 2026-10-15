# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E16.sh — M17-E16 « Monter un composant de plateforme par Helmfile » : cert-manager à la version
# épinglée sur main, émetteurs en release ordonnée par « needs », retour sur échec déclaré, cert-manager
# fonctionnel, Helmfile sans écart. Lecture seule (helmfile diff sur une copie exportée de origin/main).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E16 — Monter un composant de plateforme par Helmfile"
require_cmd jq kubectl helm git

# Tous les fichiers de releases de plateforme/k8s (main), concaténés.
_e16_releases="$(for f in $(_m17p_gl_arbre plateforme/k8s releases); do _m17p_gl_fichier plateforme/k8s "$f"; echo; done)" || _e16_releases=""
[[ -n "$_e16_releases" ]] || _e16_releases="$(_m17p_gl_fichier plateforme/k8s helmfile.yaml)" || _e16_releases=""

# Version épinglée de cert-manager : la ligne « version: » qui suit « chart: jetstack/cert-manager ».
_e16_epingle="$(awk '/chart:[[:space:]]*[^[:space:]]*cert-manager[[:space:]]*$/ {c=1; next} c && /version:/ {gsub(/["[:space:]]/, "", $2); print $2; exit} /- name:/ {c=0}' <<<"$_e16_releases")" || _e16_epingle=""
_e16_installe="$(_m17p_rel_chart cert-manager cert-manager)" || _e16_installe=""
check_cmd "cert-manager : version épinglée sur main lisible (${_e16_epingle:-?})" test -n "$_e16_epingle"
check_cmd "cert-manager : release installée = version épinglée (${_e16_installe:-absente})" test "$_e16_installe" = "cert-manager-$_e16_epingle"
check_output "cert-manager : release deployed" '^deployed$' _m17p_rel_statut cert-manager cert-manager

check_output "release emetteurs : deployed" '^deployed$' _m17p_rel_statut cert-manager emetteurs
check_cmd "ClusterIssuer step-ca-acme appartient à la release emetteurs" \
  bash -c "kubectl --kubeconfig '${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}' get clusterissuer step-ca-acme -o json 2>/dev/null | jq -e '.metadata.annotations[\"meta.helm.sh/release-name\"] == \"emetteurs\"' >/dev/null"
check_output "ClusterIssuer step-ca-acme : Ready" '^True$' \
  kube get clusterissuer step-ca-acme -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
check_cmd "releases : « needs » vers cert-manager/cert-manager déclaré" grep -Eq -- '-[[:space:]]*cert-manager/cert-manager' <<<"$_e16_releases"
check_cmd "releases : retour sur échec déclaré (rollbackOnFailure ou atomic)" grep -Eq '(rollbackOnFailure|atomic):[[:space:]]*true' <<<"$_e16_releases$(_m17p_gl_fichier plateforme/k8s releases/_communs.yaml)"
check_cmd "releases : plus aucun takeOwnership laissé en place" bash -c "! grep -Eq 'takeOwnership:[[:space:]]*true' <<<\"\$1\"" _ "$_e16_releases"

check_cmd "cert-manager : tous les Deployments disponibles" bash -c \
  "kubectl --kubeconfig '${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}' get deploy -n cert-manager -o json 2>/dev/null | jq -e '(.items | length) >= 3 and all(.items[]; (.status.availableReplicas // 0) >= (.spec.replicas // 1))' >/dev/null"
check_output "certificat apps-joker : Ready" '^True$' \
  bash -c "kubectl --kubeconfig '${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}' get certificate -A -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name == \"apps-joker\") | .status.conditions[]? | select(.type == \"Ready\") | .status'"
check_cmd "aucun Certificate d'essai laissé dans wb-essais" \
  bash -c "[ \"\$(kubectl --kubeconfig '${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}' get certificate -n wb-essais -o name 2>/dev/null | wc -l)\" -eq 0 ]"

if [[ -d "$_m17p_k8s/.git" ]]; then
  _e16_rc=0
  _m17p_helmfile_diff_vide || _e16_rc=$?
  if ((_e16_rc == 2)); then
    skip "helmfile -e par1 diff vide" "helmfile absent de ce poste"
  else
    check_cmd "helmfile -e par1 diff (origin/main) : aucun écart sur toute la plateforme" test "$_e16_rc" -eq 0
  fi
else
  check_cmd "copie de travail $_m17p_k8s présente" false
fi
