# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions régulières entre apostrophes (pas de développement voulu)
#
# check-E13.sh — M24-E13 : SSO d'Argo CD et fin des comptes locaux
# À lancer depuis adm01. Lecture seule : clients « argocd » et « argocd-cli » (wb-checks), ConfigMaps
# argocd-cm et argocd-rbac-cm, AppProject medidoc, politique réseau d'argocd-server (wb-checks du
# cluster : ni Secrets, ni argocd-secret), dernier pipeline de plateforme/k8s.

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E13 — SSO d'Argo CD et fin des comptes locaux"
require_cmd jq curl kubectl yq

# _m24o_e13_oidc TEXTE — oidc.config (YAML) : émetteur, deux clients, secret par référence, portées sans groups.
_m24o_e13_oidc() {
  local j
  j="$(yq -o=json '.' <<<"$1" 2>/dev/null || true)"
  _m24o_json "$j" --arg e "$_M24D_EMETTEUR" '.issuer == $e and .clientID == "argocd" and .cliClientID == "argocd-cli"
    and .clientSecret == "$argocd-oidc:clientSecret" and (.requestedScopes | type == "array")
    and (.requestedScopes | index("groups") == null) and (.requestedScopes | index("openid") != null)
    and ((.enablePKCEAuthentication // false) == false) and ((.rootCA // "") | contains("BEGIN CERTIFICATE"))'
}

# --- 1. Les clients --------------------------------------------------------------------------------------
_m24o_controler_client argocd confidentiel non "https://argocd.apps.par1.medisphere.internal/auth/callback"
_m24o_controler_client argocd-cli public S256 "http://localhost:8085/auth/callback"
check_cmd "plateforme/identite : tofu/clients-argocd.tf sur main (les deux clients)" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" tofu/clients-argocd.tf 'client_id *= *"argocd-cli"'

# --- 2. argocd-cm ---------------------------------------------------------------------------------------
_m24o_e13_cm="$(_m24o_k -n argocd get configmap argocd-cm -o json)"
if [[ -z "$_m24o_e13_cm" ]]; then
  _ko "Argo CD : ConfigMap argocd-cm illisible avec le compte des checks"
else
  check_cmd "argocd-cm : OIDC vers le royaume medisphere, clients argocd et argocd-cli, secret par référence \$argocd-oidc:clientSecret, portées sans « groups », racine MédiSphère" \
    _m24o_e13_oidc "$(jq -r '.data["oidc.config"] // empty' <<<"$_m24o_e13_cm")"
  check_cmd "argocd-cm : plus aucun compte local hors ci-lecture" \
    _m24o_json "$_m24o_e13_cm" '[.data | keys[] | select(test("^accounts\\.[^.]+$"))] == ["accounts.ci-lecture"]'
  check_cmd "argocd-cm : compte admin toujours désactivé, Dex non utilisé" \
    _m24o_json "$_m24o_e13_cm" '.data["admin.enabled"] == "false" and ((.data["dex.config"] // "") == "")'
fi

# --- 3. argocd-rbac-cm ----------------------------------------------------------------------------------
_m24o_e13_rbac="$(_m24o_k -n argocd get configmap argocd-rbac-cm -o json)"
_m24o_e13_politique="$(jq -r '.data["policy.csv"] // empty' <<<"$_m24o_e13_rbac" 2>/dev/null || true)"
check_cmd "argocd-rbac-cm : groupes lus dans la revendication groups, aucun rôle par défaut" \
  _m24o_json "$_m24o_e13_rbac" '((.data.scopes // "") | test("groups")) and ((.data["policy.default"] // "") == "")'
check_cmd "policy.csv : le groupe plateforme-admins reçoit role:plateforme-admin" \
  grep -Eq '^[[:space:]]*g,[[:space:]]*plateforme-admins,[[:space:]]*role:plateforme-admin[[:space:]]*$' <<<"$_m24o_e13_politique"
check_cmd "policy.csv : le groupe mediagenda reçoit role:mediagenda-equipe" \
  grep -Eq '^[[:space:]]*g,[[:space:]]*mediagenda,[[:space:]]*role:mediagenda-equipe[[:space:]]*$' <<<"$_m24o_e13_politique"
check_cmd "policy.csv : plus aucun compte de personne (karim-benali, julien-petit, nadia-roussel…)" \
  _m24o_aucune_ligne '^[[:space:]]*[gp],[[:space:]]*(karim-benali|julien-petit|nadia-roussel|lucas-martin|sophie-laurent|claire-morel)[[:space:]]*,' \
  "$_m24o_e13_politique"

# --- 4. Projet medidoc, réseau, CI ---------------------------------------------------------------------
check_cmd "AppProject medidoc : le rôle « equipe » porte le groupe medidoc (nom court)" \
  _m24o_json "$(_m24o_k -n argocd get appprojects.argoproj.io medidoc -o json)" \
  '[.spec.roles[]? | select(.name == "equipe") | .groups[]?] | index("medidoc") != null'
check_cmd "argocd-server : sortie vers sso.par1.medisphere.internal sur 443 autorisée (politique Cilium)" \
  _m24o_json "$(_m24o_cnp argocd argocd-server)" '[.spec.egress[]? | select(any(.toFQDNs[]?; .matchName == "sso.par1.medisphere.internal"))
    | .toPorts[]?.ports[]?.port] | index("443") != null'
check_output "plateforme/k8s : dernier pipeline de main réussi (tests de la politique RBAC compris)" '^success$' \
  _m24d_pipeline_main "$_M24O_P_K8S"
