# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E17.sh — M10-E17 : Horizon et l'accès des équipes
# À lancer depuis adm01. Lecture seule : HTTPS, GitLab, configuration générée sur osctl01.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E17 — Horizon et l'accès des équipes"
require_cmd curl openssl jq

_m10o_url="https://openstack.par1.medisphere.internal"
_m10o_racine=/usr/local/share/ca-certificates/medisphere-root-ca.crt
check_cmd "Horizon : HTTPS valide avec la seule racine MédiSphère" \
  curl -sS -o /dev/null --max-time "$WB_TIMEOUT" --cacert "$_m10o_racine" "$_m10o_url/auth/login/"
check_output "Horizon : la page de connexion demande le domaine" 'name="domain"|id="id_domain"' \
  curl -s --max-time "$WB_TIMEOUT" --cacert "$_m10o_racine" "$_m10o_url/auth/login/"

_m10o_g="$(_m10o_globals)"
check_cmd "globals.yml (main) : horizon_keystone_multidomain activé" \
  _m10o_globals_vaut "$_m10o_g" horizon_keystone_multidomain 'yes|true|True'
check_output "dépôt (main) : _9999-custom-settings.py fixe une session de 1800 s" '^SESSION_TIMEOUT[[:space:]]*=[[:space:]]*1800' \
  _m10o_contenu_main "$_M10O_PROJET_OS" etc/kolla/config/horizon/_9999-custom-settings.py
check_output "osctl01 (généré) : session de 1800 s" '^SESSION_TIMEOUT[[:space:]]*=[[:space:]]*1800' \
  _m10o_conf_noeud "$_M10O_CTL" /etc/kolla/horizon/_9999-custom-settings.py
check_output "osctl01 (généré) : multi-domaines actif" 'OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True' \
  _m10o_conf_noeud "$_M10O_CTL" /etc/kolla/horizon/_9998-kolla-settings.py

# Matrice : toutes les règles du VPN vers la VIP externe ne portent que 443 et 6080, et les deux.
_m10o_vpn_vip() {
  local m lignes ports
  m="$(_m10o_matrice)"
  lignes="$(grep -E 'WG_ADM' <<<"$m" | grep -E '10\.10\.50\.201|OS_VIP_EXT|VIP_EXT' || true)"
  [[ -n "$lignes" ]] || return 1
  ports="$(grep -oE 'ports:[[:space:]]*(\[[^]]*\]|[0-9]+)' <<<"$lignes" | grep -oE '[0-9]+' | sort -u | paste -sd, -)"
  [[ "$ports" == "443,6080" ]]
}
check_cmd "matrice des flux (main) : VPN d'administration vers 10.10.50.201 sur 443 et 6080 seulement" _m10o_vpn_vip
check_port "VIP externe : console noVNC (6080) joignable" 10.10.50.201 6080
