# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M25-E12 « Méthode Kubernetes et External Secrets Operator ».
# Vérifie : méthode k8s-par1/ de type kubernetes vers la VIP de l'API, rôles eso-plateforme et
# eso-wb-essais (audience, un seul compte, un seul espace), Application external-secrets saine,
# ClusterSecretStore openbao Ready et limité à des espaces, SecretStore et ExternalSecret de
# wb-essais Ready, droits du compte des checks (objets d'ESO oui, Secrets non), notes de conception.
# Lecture seule : bao_api, kube (wb-checks), ~/m25/e12/.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E12 — Méthode Kubernetes et External Secrets Operator"
require_cmd jq kubectl curl

# --- OpenBao ---------------------------------------------------------------------------------------
check_cmd "méthode k8s-par1/ montée, de type kubernetes" _m25o_auth_type k8s-par1 kubernetes
check_cmd "k8s-par1/ : API du cluster par sa VIP (https://k8s-api.par1.medisphere.internal:8443), CA fournie" \
  _m25o_json "$(_m25o_bao auth/k8s-par1/config)" '
  .data.kubernetes_host == "https://k8s-api.par1.medisphere.internal:8443"
  and ((.data.kubernetes_ca_cert // "") | test("BEGIN CERTIFICATE"))'

# _m25o_e12_role NOM COMPTE ESPACE — audience exigée, exactement un compte et un espace.
_m25o_e12_role() {
  _m25o_json "$(_m25o_bao "auth/k8s-par1/role/$1")" --arg c "$2" --arg e "$3" '
    .data.audience == "openbao.medisphere.internal"
    and .data.bound_service_account_names == [$c]
    and .data.bound_service_account_namespaces == [$e]'
}
check_cmd "rôle eso-plateforme : audience, compte external-secrets de l'espace external-secrets seulement" \
  _m25o_e12_role eso-plateforme external-secrets external-secrets
check_cmd "rôle eso-wb-essais : audience, compte eso de wb-essais seulement" _m25o_e12_role eso-wb-essais eso wb-essais
check_cmd "politique eso-wb-essais : lecture de kv/data/wb-essais/ seulement" \
  bash -c 'grep -q "kv/data/wb-essais/" <<<"$1" && ! grep -Eq "\"kv/data/\*\"|\"kv/\*\"|plateforme|mediagenda|medidoc" <<<"$1"' _ \
  "$(_m25o_politique eso-wb-essais)"

# --- ESO -------------------------------------------------------------------------------------------
check_cmd "Application Argo CD external-secrets : Synced et Healthy" _m25o_app_ok external-secrets
_m25o_e12_api() {
  local r
  r="$(_m25o_k api-resources --api-group=external-secrets.io -o wide)"
  grep -q 'external-secrets.io/v1 ' <<<"$r" && grep -q '^externalsecrets ' <<<"$r" && grep -q '^clustersecretstores ' <<<"$r"
}
check_cmd "API external-secrets.io/v1 disponible (externalsecrets, clustersecretstores)" _m25o_e12_api

_m25o_e12_css="$(_m25o_k get clustersecretstores.external-secrets.io openbao -o json)"
check_cmd "ClusterSecretStore openbao : Ready" _m25o_pret "$_m25o_e12_css"
check_cmd "ClusterSecretStore openbao : fournisseur vault (KV v2, méthode k8s-par1, rôle eso-plateforme, audience)" \
  _m25o_json "$_m25o_e12_css" '
  .spec.provider.vault as $v
  | $v.server == "https://openbao.par1.medisphere.internal:8200" and $v.path == "kv" and $v.version == "v2"
    and $v.auth.kubernetes.mountPath == "k8s-par1" and $v.auth.kubernetes.role == "eso-plateforme"
    and ($v.auth.kubernetes.serviceAccountRef.audiences | index("openbao.medisphere.internal")) != null'
check_cmd "ClusterSecretStore openbao : limité par conditions à une liste d'espaces (sans wb-essais ni espace applicatif)" \
  _m25o_json "$_m25o_e12_css" '
  ([.spec.conditions[]?.namespaces[]?] | length) > 0
  and ([.spec.conditions[]? | .namespaceSelector, .namespaceRegexes] | map(select(. != null)) | length) == 0
  and ([.spec.conditions[]?.namespaces[]?] | all(test("^(mediagenda|medidoc|wb-essais)") | not))'

check_cmd "SecretStore openbao de wb-essais : Ready" _m25o_objet_pret secretstores.external-secrets.io openbao wb-essais
check_cmd "ExternalSecret premier-secret de wb-essais : Ready (Secret synchronisé)" _m25o_es_pret wb-essais premier-secret
check_cmd "kv/wb-essais/premier-secret existe" _m25o_kv_existe wb-essais/premier-secret

# --- Droits du compte des checks ---------------------------------------------------------------------
check_cmd "wb-checks lit les ExternalSecret (ClusterRole wb-checks-securite étendue)" \
  _m25o_peut list externalsecrets.external-secrets.io wb-essais
check_cmd "wb-checks lit les ClusterSecretStore" _m25o_peut list clustersecretstores.external-secrets.io
# Réponse « no » explicite : une API injoignable (réponse vide) ne doit pas passer pour un refus.
_m25o_e12_pas_secrets() { [[ "$(_m25o_k auth can-i get secrets -n wb-essais)" == no ]]; }
check_cmd "wb-checks ne lit toujours PAS les Secrets" _m25o_e12_pas_secrets

# --- Notes -----------------------------------------------------------------------------------------
check_cmd "m25/e12/conception.md : choix du jeton de TokenReview et droits associés (auth-delegator)" \
  _m25o_local e12/conception.md 'auth-delegator|tokenreview'
check_cmd "m25/e12/conception.md : refus notés (audience, compte, espace)" \
  _m25o_local e12/conception.md 'audience'
