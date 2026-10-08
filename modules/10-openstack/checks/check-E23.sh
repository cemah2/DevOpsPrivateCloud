# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E23.sh — M10-E23 : Politiques d'accès et rôles de lecture
# À lancer depuis adm01. Lecture seule : Keystone, GitLab, configuration générée sur osctl01, listes avec les clouds medisphere-audit et medisphere-support.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E23 — Politiques d'accès et rôles de lecture"
require_cmd openstack jq

check_cmd "le rôle support existe" bash -c 'openstack --os-cloud "$1" role show support >/dev/null 2>&1' _ "$_M10O_CLOUD"

_m10o_sec="$(_m10o_os role assignment list --group equipe-securite --group-domain "$_M10O_DOMAINE" --names -f json || echo '[]')"
check_cmd "equipe-securite : une seule attribution, reader hérité sur le domaine medisphere" \
  jq -e 'length == 1 and (.[0].Role | startswith("reader")) and (.[0].Domain | startswith("medisphere")) and (.[0].Inherited == true)' <<<"$_m10o_sec"

_m10o_sophie="$(_m10o_os role assignment list --effective --user sophie.laurent --user-domain "$_M10O_DOMAINE" --names -f json || echo '[]')"
for _m10o_p in mediagenda-dev mediagenda-prod; do
  check_cmd "sophie.laurent : reader, et seulement reader, sur $_m10o_p" \
    jq -e --arg p "$_m10o_p" '[.[] | select(.Project | startswith($p + "@")) | .Role | split("@")[0]] | unique == ["reader"]' <<<"$_m10o_sophie"
done

_m10o_sup="$(_m10o_os role assignment list --group equipe-support --group-domain "$_M10O_DOMAINE" --names -f json || echo '[]')"
for _m10o_p in mediagenda-dev mediagenda-prod; do
  check_cmd "equipe-support : support sur $_m10o_p, sans member ni admin" \
    jq -e --arg p "$_m10o_p" '[.[] | select(.Project | startswith($p + "@")) | .Role | split("@")[0]] as $r
                               | ($r | index("support")) != null and ($r | index("member")) == null and ($r | index("admin")) == null' <<<"$_m10o_sup"
done

check_output "dépôt (main) : la politique de Nova mentionne le rôle support" 'role:support' \
  _m10o_contenu_main "$_M10O_PROJET_OS" etc/kolla/config/nova/policy.yaml
check_output "osctl01 (généré) : politique de nova-api avec le rôle support" 'role:support' \
  _m10o_conf_noeud "$_M10O_CTL" /etc/kolla/nova-api/policy.yaml
check_output "osctl01 (généré) : copie de la politique pour Horizon avec le rôle support" 'role:support' \
  _m10o_conf_noeud "$_M10O_CTL" /etc/kolla/horizon/nova_policy.yaml

for _m10o_c in medisphere-support medisphere-audit; do
  if _m10o_cloud_existe "$_m10o_c"; then
    check_cmd "cloud $_m10o_c : la liste des instances du projet fonctionne" \
      bash -c 'openstack --os-cloud "$1" server list -f json >/dev/null 2>&1' _ "$_m10o_c"
  else
    _ko "cloud $_m10o_c absent de ~/.config/openstack/clouds.yaml"
  fi
done
