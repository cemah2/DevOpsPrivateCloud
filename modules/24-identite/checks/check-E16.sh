# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres entre apostrophes
#
# check-E16.sh — M24-E16 : kubectl par OIDC : authentification structurée et kubelogin
# À lancer depuis adm01. Lecture seule : client « kubernetes » (wb-checks) ; pods statiques de
# kube-apiserver et ClusterRole wb-checks-securite (wb-checks du cluster) ; SSH admin@k8s-cp0N (stat,
# grep en sudo -n, curl vers l'émetteur) ; ~/.kube/config d'adm01 ; et une requête VOLONTAIREMENT
# refusée : un jeton de Keycloak destiné au client wb-checks, présenté au serveur d'API (SelfSubjectReview,
# qui n'écrit rien), doit recevoir 401.

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E16 — kubectl par OIDC : authentification structurée et kubelogin"
require_cmd jq curl kubectl ssh

_M24O_E16_FICHIER=/etc/kubernetes/authentification/config.yaml

# _m24o_e16_code_autre_audience — code HTTP du serveur d'API pour un jeton wb-checks (attendu : 401).
_m24o_e16_code_autre_audience() {
  local kc="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" serveur ca jeton
  [[ -r "$kc" ]] || return 0
  serveur="$(kubectl --kubeconfig "$kc" config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
  ca="$(kubectl --kubeconfig "$kc" config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || true)"
  jeton="$(_m24o_jeton_wb_checks)"
  [[ -n "$serveur" && -n "$ca" && -n "$jeton" ]] || return 0
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert <(base64 -d <<<"$ca") \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") -H 'Content-Type: application/json' \
    -d '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
    "$serveur/apis/authentication.k8s.io/v1/selfsubjectreviews" 2>/dev/null || true
}

# --- 1. Le client ------------------------------------------------------------------------------------------
_m24o_controler_client kubernetes public S256 "http://localhost:8000" "http://localhost:18000"

# --- 2. Les serveurs d'API ---------------------------------------------------------------------------------
_m24o_e16_pods="$(_m24o_k -n kube-system get pods -l component=kube-apiserver -o json)"
check_cmd "kube-apiserver : les 3 pods ont --authentication-config=$_M24O_E16_FICHIER" \
  _m24o_json "$_m24o_e16_pods" --arg f "--authentication-config=$_M24O_E16_FICHIER" \
  '(.items | length) == 3 and all(.items[]; [.spec.containers[0].command[]] | index($f) != null)'
check_cmd "kube-apiserver : aucune option --oidc-* (exclusives de l'authentification structurée)" \
  _m24o_json "$_m24o_e16_pods" '(.items | length) >= 1 and all(.items[]; all(.spec.containers[0].command[]; startswith("--oidc-") | not))'
check_cmd "kube-apiserver : le DOSSIER /etc/kubernetes/authentification est monté (rechargement à chaud)" \
  _m24o_json "$_m24o_e16_pods" '(.items | length) == 3
    and all(.items[]; any(.spec.volumes[]?; .hostPath.path == "/etc/kubernetes/authentification"))'

for _m24o_e16_n in "${_M24O_CP[@]}"; do
  check_ssh_output "$_m24o_e16_n : $_M24O_E16_FICHIER en 600, propriété de root" "$_m24o_e16_n" '^600 root$' \
    "sudo -n stat -c '%a %U' $_M24O_E16_FICHIER"
  check_ssh "$_m24o_e16_n : audience kubernetes, préfixes oidc:, refus de system:, émetteur du royaume" "$_m24o_e16_n" \
    "sudo -n grep -q 'url: $_M24D_EMETTEUR' $_M24O_E16_FICHIER \
     && sudo -n grep -Eq '^ *- kubernetes *$' $_M24O_E16_FICHIER \
     && [ \"\$(sudo -n grep -c 'prefix: \"oidc:\"' $_M24O_E16_FICHIER)\" -ge 2 ] \
     && sudo -n grep -q \"startsWith('system:')\" $_M24O_E16_FICHIER"
  check_ssh "$_m24o_e16_n : l'émetteur est joignable en TLS vérifié (flux K8S_CP → VIP lb 443)" "$_m24o_e16_n" \
    "curl -sf --max-time 5 -o /dev/null $_M24D_EMETTEUR/.well-known/openid-configuration"
done

check_output "Un jeton de Keycloak destiné à un AUTRE client (wb-checks) est refusé par le serveur d'API (401)" '^401$' \
  _m24o_e16_code_autre_audience

# --- 3. adm01 ---------------------------------------------------------------------------------------------------
check_cmd "adm01 : kubelogin installé (kubectl oidc-login)" kubectl oidc-login --help
_m24o_e16_kc="$(kubectl config view -o json 2>/dev/null || true)"
check_cmd "adm01 : contexte k8s-par1-oidc → utilisateur oidc (kubelogin, client public kubernetes, sans secret)" \
  _m24o_json "$_m24o_e16_kc" --arg e "--oidc-issuer-url=$_M24D_EMETTEUR" '
    any(.contexts[]; .name == "k8s-par1-oidc" and .context.user == "oidc")
    and any(.users[]; .name == "oidc" and (.user.exec.args | index("oidc-login") != null)
      and (.user.exec.args | index($e) != null) and (.user.exec.args | index("--oidc-client-id=kubernetes") != null)
      and all(.user.exec.args[]; startswith("--oidc-client-secret") | not))'

# --- 4. Vérifications du bloc F ----------------------------------------------------------------------------
check_cmd "ClusterRole wb-checks-securite : agrégée aux vérifications, en lecture, sans Secrets" \
  _m24o_json "$(_m24o_k get clusterrole wb-checks-securite -o json)" '
    .metadata.labels["workbook.medisphere.internal/checks"] == "true"
    and all(.rules[]; (.verbs - ["get", "list", "watch"]) == [] and ((.resources // []) | index("secrets") == null))'
