# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S09.sh — F1-S09 « Raccrocher l'identité et les secrets ».
# Lecture seule : configuration de la méthode k8s-par1 d'OpenBao (AppRole wb-checks : auth/+/config,
# jamais une valeur de secret), ConfigMap publique kube-root-ca.crt, objets d'ESO (statuts seulement),
# pods du plan de contrôle, liaisons RBAC, client « kubernetes » de Keycloak, pipelines de
# plateforme/secrets.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S09 — Raccrocher l'identité et les secrets"
require_cmd kubectl jq curl openssl

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi

# --- OpenBao fait confiance au nouveau cluster -------------------------------------------------------
_f1_s09_ca_k="$(_f1c_ca_cluster)"
_f1_s09_ca_b="$(_f1c_ca_openbao)"
check_cmd "autorité du cluster lue (ConfigMap kube-root-ca.crt)" test -n "$_f1_s09_ca_k"
check_cmd "configuration de auth/k8s-par1 lue dans OpenBao (AppRole wb-checks)" test -n "$_f1_s09_ca_b"
check_cmd "OpenBao (auth/k8s-par1/config) fait confiance à l'autorité du cluster ACTUEL" \
  test -n "$_f1_s09_ca_k" -a "$_f1_s09_ca_k" = "$_f1_s09_ca_b"
_f1_s09_cfg="$(bao_api auth/k8s-par1/config 2>/dev/null || true)"
check_cmd "auth/k8s-par1 : hôte = la VIP de l'API (https://k8s-api.par1.medisphere.internal:8443)" \
  jq -e '.data.kubernetes_host == "https://k8s-api.par1.medisphere.internal:8443"' <<<"${_f1_s09_cfg:-null}"
_f1_s09_role="$(bao_api auth/k8s-par1/role/eso-plateforme 2>/dev/null || true)"
check_cmd "rôle eso-plateforme : audience openbao.medisphere.internal, compte external-secrets/external-secrets" \
  jq -e '.data.audience == "openbao.medisphere.internal"
         and (.data.bound_service_account_names | index("external-secrets"))
         and (.data.bound_service_account_namespaces | index("external-secrets"))' <<<"${_f1_s09_role:-null}"
_f1_s09_pip="$(gitlab_api "projects/$(_f1c_enc plateforme/secrets)/pipelines?ref=main&per_page=1" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true)"
_f1_s09_ne="$(_f1c_naissance_iso)"
check_cmd "plateforme/secrets : dernier pipeline de main réussi, postérieur à la naissance du cluster" \
  jq -e --arg n "${_f1_s09_ne:-9999}" '.status == "success" and (.created_at // "") > $n' <<<"${_f1_s09_pip:-null}"

# --- ESO -------------------------------------------------------------------------------------------------
check_cmd "espace external-secrets : contrôleur, webhook et contrôleur de certificats prêts" _f1c_espace_pret external-secrets
check_cmd "ClusterSecretStore openbao prêt" _f1c_kq 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
  clustersecretstores.external-secrets.io openbao
check_cmd "tous les SecretStores du cluster prêts (au moins un)" _f1c_kq \
  '(.items | length > 0) and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
  secretstores.external-secrets.io -A
_f1_s09_nb_es="$(_f1c_nb externalsecrets.external-secrets.io -A)"
_f1_s09_ko="$(_f1c_es_non_prets | head -n 5 | paste -sd ' ' -)"
check_cmd "tous les ExternalSecrets prêts ($_f1_s09_nb_es)${_f1_s09_ko:+ — en erreur : $_f1_s09_ko}" \
  test "$_f1_s09_nb_es" -gt 0 -a -z "$_f1_s09_ko"
check_cmd "ExternalSecrets d'amorçage repris : repo-creds-plateforme (argocd) prêt" _f1c_kq \
  'any(.status.conditions[]?; .type == "Ready" and .status == "True")' -n argocd externalsecrets.external-secrets.io repo-creds-plateforme

# --- Identité des personnes ------------------------------------------------------------------------------------
check_cmd "les trois serveurs d'API lisent /etc/kubernetes/authentification/config.yaml" _f1c_kq \
  '(.items | length == 3) and all(.items[]; any(.spec.containers[0].command[]; . == "--authentication-config=/etc/kubernetes/authentification/config.yaml"))' \
  -n kube-system pods -l component=kube-apiserver
check_cmd "liaisons RBAC oidc-* présentes et liées à des groupes oidc:" _f1c_kq '
  [.items[] | select(.metadata.name | startswith("oidc-"))] as $l
  | ($l | length > 0) and any($l[]; any(.subjects[]?; .kind == "Group" and (.name | startswith("oidc:"))))' clusterrolebindings
check_cmd "liaison de plateforme-admins (groupe oidc:plateforme-admins)" _f1c_kq \
  'any(.items[]; any(.subjects[]?; .kind == "Group" and .name == "oidc:plateforme-admins"))' clusterrolebindings
check_cmd "aucune liaison medisphere:* de l'ancien schéma d'accès (M14, retirées en M24-E17)" _f1c_kq \
  '[.items[] | select(.metadata.name | startswith("medisphere:"))] | length == 0' clusterrolebindings
check_cmd "Keycloak : client « kubernetes » du royaume medisphere actif" \
  bash -c '[[ "$(jq -r ".[0].enabled // false" <<<"$1")" == true ]]' _ "$(keycloak_api 'clients?clientId=kubernetes' 2>/dev/null || echo '[]')"

# --- Signatures d'images -----------------------------------------------------------------------------------------
if _f1c_lit imagevalidatingpolicies.policies.kyverno.io; then
  check_cmd "Kyverno : exiger-signature-medisphere présente, en Deny, failurePolicy Fail" _f1c_kq \
    '.spec.validationActions == ["Deny"] and .spec.failurePolicy == "Fail"' imagevalidatingpolicies.policies.kyverno.io exiger-signature-medisphere
else
  skip "politique exiger-signature-medisphere" "Kyverno pas encore revenu (S10) ou illisible par le compte des checks"
fi
