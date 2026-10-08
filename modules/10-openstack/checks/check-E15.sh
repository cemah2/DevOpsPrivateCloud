# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E15.sh — M10-E15 : OpenTofu et le provider OpenStack
# À lancer depuis adm01. Lecture seule : GitLab (plateforme/infra), API OpenStack.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E15 — OpenTofu et le provider OpenStack"
require_cmd openstack jq curl

_m10o_racine=envs/openstack-projets
_m10o_versions="$(_m10o_contenu_main "$_M10O_PROJET_INFRA" "$_m10o_racine/versions.tf")"
check_cmd "$_m10o_racine (main) : provider terraform-provider-openstack/openstack contraint à ~> 3.4" \
  bash -c 'grep -q "terraform-provider-openstack/openstack" <<<"$1" && grep -Eq "version[[:space:]]*=[[:space:]]*\"~>[[:space:]]*3\.4(\.[0-9]+)?\"" <<<"$1"' _ "$_m10o_versions"
_m10o_tf_tout() {
  local f
  while IFS= read -r f; do
    [[ "$f" == *.tf || "$f" == *.tfvars ]] && _m10o_contenu_main "$_M10O_PROJET_INFRA" "$f"
  done < <(_m10o_arbre_main "$_M10O_PROJET_INFRA" "$_m10o_racine")
}
_m10o_tf="$(_m10o_tf_tout || true)"
check_cmd "$_m10o_racine (main) : configuration présente, avec les deux projets de MédiAgenda" \
  bash -c 'grep -q "mediagenda-dev" <<<"$1" && grep -q "mediagenda-prod" <<<"$1"' _ "$_m10o_tf"
check_cmd "$_m10o_racine (main) : aucune ressource supprimée en 3.0 (compute_floatingip*, compute_secgroup)" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "openstack_compute_(floatingip|floatingip_associate|secgroup)_v2" <<<"$1"' _ "$_m10o_tf"
check_cmd "$_m10o_racine (main) : aucun secret (mot de passe, secret d'application credential)" \
  bash -c '[[ -n "$1" ]] && ! grep -Eiq "(application_credential_secret|password)[[:space:]]*=[[:space:]]*\"[^\"$]" <<<"$1"' _ "$_m10o_tf"
_m10o_ci="$(_m10o_contenu_main "$_M10O_PROJET_INFRA" .gitlab-ci.yml)"
check_cmd "pipeline de plateforme/infra (main) : un plan et un apply pour openstack-projets" \
  bash -c 'grep -Eq "^[^#]*plan[^#]*openstack-projets" <<<"$1" && grep -Eq "^[^#]*apply[^#]*openstack-projets" <<<"$1"' _ "$_m10o_ci"

_m10o_ext="$(_m10o_os network show -f value -c id ext-net || true)"
for _m10o_p in mediagenda-dev mediagenda-prod; do
  _m10o_pid="$(_m10o_projet_id "$_m10o_p")"
  _m10o_net="$(_m10o_os network list --project "${_m10o_pid:-x}" --name "$_m10o_p-net" -f json --long | jq '.[0] // {}' 2>/dev/null || echo '{}')"
  check_cmd "$_m10o_p-net : existe dans son projet, étiqueté tofu" \
    jq -e '(.Tags // .tags // []) | tostring | test("tofu")' <<<"$_m10o_net"
  check_output "$_m10o_p-net : MTU 1500" '^1500$' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" network show -f value -c mtu "$1" 2>/dev/null' _ "$(jq -r '.ID // empty' <<<"$_m10o_net")" "$_M10O_CLOUD"
  _m10o_rt="$(_m10o_os router show -f json "$_m10o_p-routeur" || true)"
  check_cmd "$_m10o_p-routeur : relié à ext-net" \
    jq -e --arg e "$_m10o_ext" '$e != "" and (.external_gateway_info | tostring | contains($e))' <<<"$_m10o_rt"
  check_output "$_m10o_p-routeur : une interface dans le sous-réseau du projet" '^[1-9]' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" port list --router "$1" --device-owner network:router_interface -f value -c ID 2>/dev/null | wc -l' \
    _ "$(jq -r '.id // empty' <<<"$_m10o_rt")" "$_M10O_CLOUD"
done

_m10o_ac="$(_m10o_os application credential list --user svc-tofu --user-domain Default -f json || true)"
check_cmd "application credential tofu-openstack-projets (svc-tofu) : existe, avec une expiration" \
  jq -e 'map(select(.Name == "tofu-openstack-projets" and ((.["Expires At"] // .expires_at // "") | tostring | test("^[0-9]{4}-")))) | length == 1' <<<"$_m10o_ac"
check_cmd "accès d'OpenTofu : openstack-tofu.env (dossier workbook) en mode 600" _m10o_mode600 "$_M10O_CFG/openstack-tofu.env"
