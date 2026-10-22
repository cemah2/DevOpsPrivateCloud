# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions régulières entre apostrophes (pas de développement voulu)
#
# check-E12.sh — M24-E12 : SSO de Grafana : rôles, organisations et équipes
# À lancer depuis adm01. Lecture seule : client « grafana » (wb-checks), réglages publics de Grafana
# (compte de service Viewer des checks), Deployment et politique réseau de l'espace supervision
# (wb-checks du cluster, jamais les Secrets), fichiers sur main (GitLab).
# Non vérifié ici (le compte Viewer ne lit pas les API d'administration) : la liste des comptes locaux
# et le rôle effectif de chaque personne ; voir le corrigé pour les contrôler en « admin ».

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E12 — SSO de Grafana : rôles, organisations et équipes"
require_cmd jq curl kubectl

# _m24o_e12_cidr_seul JSON — la politique grafana-sortie n'ouvre QUE la VIP lb sur 443.
_m24o_e12_cidr_seul() {
  _m24o_json "$1" '[.spec.egress[]?] as $e | ($e | length) >= 1
    and all($e[]; (.toCIDR // []) == ["10.10.70.200/32"] and ([.toPorts[]?.ports[]?.port] == ["443"])
      and (has("toEntities") | not) and (has("toEndpoints") | not) and (has("toCIDRSet") | not))'
}

# _m24o_e12_valeurs_ok TEXTE — generic_oauth avec PKCE, autorité montée, rôle strict, organisations.
_m24o_e12_valeurs_ok() {
  grep -Eq 'use_pkce: *true' <<<"$1" && grep -Eq 'tls_client_ca: */etc/grafana/racine/ca\.crt' <<<"$1" \
    && grep -Eq 'role_attribute_strict: *true' <<<"$1" && grep -Eq 'org_mapping:' <<<"$1"
}

# --- 1. Le client ---------------------------------------------------------------------------------------
_m24o_controler_client grafana confidentiel S256 \
  "https://grafana.apps.par1.medisphere.internal/login/generic_oauth"
check_cmd "plateforme/identite : tofu/clients-grafana.tf sur main" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" tofu/clients-grafana.tf 'client_id *= *"grafana"'

# --- 2. Le chemin du secret et la configuration -------------------------------------------------------
_m24o_e12_deploy="$(_m24o_k -n supervision get deployment kps-grafana -o json)"
check_cmd "Grafana : le déploiement charge le Secret grafana-oidc en variables d'environnement" \
  _m24o_json "$_m24o_e12_deploy" '[.spec.template.spec.containers[] | select(.name == "grafana")
    | .envFrom[]? | .secretRef.name] | index("grafana-oidc") != null'
check_cmd "Grafana : la racine MédiSphère (ConfigMap racine-medisphere) est montée dans le pod" \
  _m24o_json "$_m24o_e12_deploy" '[.spec.template.spec.volumes[]? | .configMap.name] | index("racine-medisphere") != null'
_m24o_e12_values="$(_m24d_contenu_main "$_M24O_P_OBS" kps/values.yaml)"
check_cmd "kps/values.yaml : generic_oauth avec PKCE, autorité de confiance et role_attribute_strict" \
  _m24o_e12_valeurs_ok "$_m24o_e12_values"
check_cmd "kps/values.yaml : aucun secret de client écrit en clair (client_secret)" \
  _m24o_aucune_ligne '^[[:space:]]*client_secret:[[:space:]]*[^[:space:]]' "$_m24o_e12_values"
check_cmd "supervision : politique grafana-sortie, Grafana ne sort que vers la VIP lb sur 443" \
  _m24o_e12_cidr_seul "$(_m24o_cnp supervision grafana-sortie)"

# --- 3. Ce que Grafana annonce -----------------------------------------------------------------------------
_m24o_e12_reglages="$(grafana_api frontend/settings 2>/dev/null || true)"
if [[ -z "$_m24o_e12_reglages" ]]; then
  _ko "Grafana : réglages illisibles avec le compte de service des checks (grafana-checks.token)"
else
  check_cmd "Grafana : le fournisseur generic_oauth (SSO MédiSphère) est actif" \
    _m24o_json "$_m24o_e12_reglages" '.oauth.generic_oauth != null'
  check_cmd "Grafana : plus de formulaire de connexion local (disable_login_form)" \
    _m24o_json "$_m24o_e12_reglages" '.disableLoginForm == true'
fi

# --- 4. Équipes et organisation en code --------------------------------------------------------------
check_cmd "observabilite-grafana : les membres de l'organisation « Sécurité » ne sont plus gérés par OpenTofu (ignore_changes)" \
  _m24o_fichier_main "$_M24O_P_INFRA" observabilite-grafana/organisation-securite.tf 'ignore_changes'
check_cmd "observabilite-grafana : les équipes ne gardent que les comptes existants (source grafana_users)" \
  _m24o_fichier_main "$_M24O_P_INFRA" observabilite-grafana/utilisateurs.tf 'data +"grafana_users"'
