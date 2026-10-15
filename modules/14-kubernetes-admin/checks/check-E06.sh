# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées par bash -c
#
# check-E06.sh — M14-E06 : kubectl, kubeconfig et k9s
# À lancer depuis adm01. Lecture seule : « kube » (kubeconfig des checks : c'est ce que l'exercice
# crée), puis TON kubeconfig personnel pour deux appels d'identité (auth whoami, auth can-i),
# fichiers de adm01, API GitLab en GET.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E06 — kubectl, kubeconfig et k9s"
require_cmd jq kubectl openssl

_m14d_e06_moi="${WB_MOI:-}"
_m14d_e06_perso="$HOME/.kube/config"

# --- 1. Le kubeconfig des vérifications (wb-checks) ------------------------------------------------
check_cmd "$_M14D_KCFG existe, en 600" bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_M14D_KCFG"
check_output "« kube » répond avec le compte de service wb-system/wb-checks" '^system:serviceaccount:wb-system:wb-checks$' \
  kube auth whoami -o jsonpath='{.status.userInfo.username}'
check_output "wb-checks lit les nœuds" '^node/k8s-cp01$' kube get node k8s-cp01 -o name
check_output "wb-checks ne peut PAS lire les Secrets" '^no' kube auth can-i get secrets --all-namespaces
check_output "wb-checks ne peut PAS modifier le cluster (supprimer un pod)" '^no' kube auth can-i delete pods --all-namespaces
check_output "wb-checks n'emprunte pas d'identité (impersonate)" '^no' kube auth can-i impersonate users
check_output "kubeconfig des checks : point d'accès https://$_M14D_API:8443" "^https://${_M14D_API//./\\.}:8443$" \
  kubectl --kubeconfig "$_M14D_KCFG" config view -o jsonpath='{.clusters[0].cluster.server}'

# --- 2. Les objets de plateforme/k8s appliqués --------------------------------------------------------
_m14d_e06_espaces() { kube get namespace wb-system wb-essais -o name 2>/dev/null | sort | paste -sd " "; }
check_output "Espaces wb-system et wb-essais" '^namespace/wb-essais namespace/wb-system$' _m14d_e06_espaces
check_cmd "ClusterRole wb-checks agrégée (étiquette workbook.medisphere.internal/checks=true)" _m14d_json \
  "$(kube get clusterrole wb-checks -o json 2>/dev/null || true)" \
  '.aggregationRule.clusterRoleSelectors[0].matchLabels["workbook.medisphere.internal/checks"] == "true" and (.rules | length) >= 3'
check_cmd "ServiceAccount wb-checks sans jeton monté automatiquement" _m14d_json \
  "$(kube -n wb-system get serviceaccount wb-checks -o json 2>/dev/null || true)" '.automountServiceAccountToken == false'
check_output "Liaison medisphere:plateforme-admins : groupe → cluster-admin" '^cluster-admin Group medisphere:plateforme-admins$' \
  kube get clusterrolebinding medisphere:plateforme-admins -o jsonpath='{.roleRef.name} {.subjects[0].kind} {.subjects[0].name}'
check_output "Objets appliqués par « task appliquer » (gestionnaire de champs plateforme-k8s)" 'plateforme-k8s' \
  kube get clusterrolebinding wb-checks --show-managed-fields -o jsonpath='{.metadata.managedFields[*].manager}'

# --- 3. Ton identité personnelle ------------------------------------------------------------------------
if [[ -z "$_m14d_e06_moi" ]]; then
  skip "Identité personnelle (WB_MOI)" "WB_MOI vide dans lab/lab.env"
else
  _m14d_e06_crt="$(kubectl --kubeconfig "$_m14d_e06_perso" config view --raw \
    -o jsonpath="{.users[?(@.name==\"$_m14d_e06_moi\")].user.client-certificate-data}" 2>/dev/null | base64 -d 2>/dev/null || true)"
  check_output "Kubeconfig personnel : certificat de $_m14d_e06_moi, groupe medisphere:plateforme-admins" \
    "^subject=CN=${_m14d_e06_moi},O=medisphere:plateforme-admins$" \
    bash -c 'openssl x509 -noout -subject -nameopt RFC2253 <<<"$1"' _ "$_m14d_e06_crt"
  check_cmd "Kubeconfig personnel : certificat valable, 7 jours au plus" bash -c \
    'openssl x509 -noout -checkend 0 <<<"$1" >/dev/null && ! openssl x509 -noout -checkend $((7*86400+3600)) <<<"$1" >/dev/null' \
    _ "$_m14d_e06_crt"
  check_cmd "Kubeconfig personnel en 600, contexte courant k8s-par1" bash -c \
    '[[ "$(stat -c %a "$1")" == 600 && "$(kubectl --kubeconfig "$1" config current-context)" == k8s-par1 ]]' _ "$_m14d_e06_perso"
  check_output "Ton identité est reconnue par le cluster (auth whoami)" "^${_m14d_e06_moi} .*medisphere:plateforme-admins" \
    kubectl --kubeconfig "$_m14d_e06_perso" --context k8s-par1 --request-timeout="${WB_TIMEOUT}s" auth whoami \
    -o jsonpath='{.status.userInfo.username} {.status.userInfo.groups}'
fi
check_cmd "Aucune copie en clair d'admin.conf ou de super-admin.conf sur adm01 (~/.kube, dossier de session)" bash -c \
  '! grep -rlsE "kubernetes-(super-)?admin" "$HOME/.kube" "${XDG_RUNTIME_DIR:-/nonexistent}" >/dev/null 2>&1'

# --- 4. Outils ------------------------------------------------------------------------------------------
check_output "krew : greffons ctx, ns et neat installés" '^ctx neat ns$' \
  bash -c 'kubectl krew list 2>/dev/null | awk "NR > 0 && \$1 ~ /^(ctx|ns|neat)$/ {print \$1}" | sort | paste -sd " "'
check_output "k9s 0.51" '^Version +v?0\.51\.' k9s version --short

# --- 5. Le code et la documentation ---------------------------------------------------------------------
for _m14d_e06_f in espaces/wb-system.yaml espaces/wb-essais.yaml rbac/plateforme-admins.yaml rbac/wb-checks.yaml \
  outils/kubeconfig-personnel.sh outils/kubeconfig-checks.sh; do
  check_cmd "plateforme/k8s (main) : $_m14d_e06_f" _m14d_fichier_main plateforme/k8s "$_m14d_e06_f"
done
check_output "plateforme/medisphere (main) : docs/kubernetes/acces.md (identités, bris de glace, exception wb-checks)" 'wb-checks' \
  _m14d_contenu_main plateforme/medisphere docs/kubernetes/acces.md
