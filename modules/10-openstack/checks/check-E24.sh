# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E24.sh — M10-E24 « La haute disponibilité du plan de contrôle »
# Lecture seule : adresses et configuration générée de osctl01, page de statistiques d'HAProxy
# (sans identifiants : on attend un refus), état des conteneurs, services OpenStack, GitLab.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E24 — La haute disponibilité du plan de contrôle"
require_cmd openstack jq ssh curl
_m10p_charger

title "Points d'entrée"
check_ssh "osctl01 : VIP interne 10.10.50.200 portée par ens18" osctl01 \
  'ip -br -4 addr show dev ens18 | grep -Eq "[[:space:]]10\.10\.50\.200/"'
check_ssh "osctl01 : VIP externe 10.10.50.201 portée par ens18" osctl01 \
  'ip -br -4 addr show dev ens18 | grep -Eq "[[:space:]]10\.10\.50\.201/"'
check_ssh "keepalived de Kolla : numéro de routeur virtuel 150" osctl01 \
  'sudo -n grep -Eq "virtual_router_id[[:space:]]+150([^0-9]|$)" /etc/kolla/keepalived/keepalived.conf'
check_ssh "keepalived de Kolla : aucun numéro de routeur virtuel 50 (celui des passerelles)" osctl01 \
  'c=$(sudo -n cat /etc/kolla/keepalived/keepalived.conf) && ! printf "%s\n" "$c" | grep -Eq "virtual_router_id[[:space:]]+50([^0-9]|$)"'
check_http "page de statistiques d'HAProxy en service et protégée (401 sans identifiants)" \
  "http://10.10.50.51:1984/" 401

title "État après les pannes"
for _m10_h in "${_M10P_NOEUDS[@]}"; do
  check_cmd "$_m10_h : aucun conteneur unhealthy, arrêté ou en redémarrage" _m10p_conteneurs_sains "$_m10_h"
done
check_cmd "services de calcul : tous activés et « up »" _m10p_calcul_up
check_cmd "agents réseau OVN : tous vivants, passerelle présente" _m10p_agents_vivants
check_cmd "services Cinder (scheduler, volume, backup) : « up »" _m10p_volumes_up
check_ssh "osctl01 : MariaDB (Galera) synchronisée" osctl01 \
  'sudo -n docker inspect -f "{{.State.Health.Status}}" mariadb | grep -qx healthy'
check_ssh "osctl01 : RabbitMQ en service" osctl01 \
  'sudo -n docker exec rabbitmq rabbitmqctl -q status >/dev/null 2>&1'

title "Documentation et plan à trois contrôleurs"
check_cmd "plateforme/medisphere : docs/cloud/haute-disponibilite.md (Galera, RabbitMQ, OVN, VRID 150, plan de données)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/haute-disponibilite.md \
  'galera' 'rabbitmq' 'ovn' '150' 'plan de donn'
check_cmd "haute-disponibilite.md : durées de reprise mesurées (minutes ou secondes)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/haute-disponibilite.md '[0-9]+ ?(min|s)([^a-z]|$)'
check_cmd "plateforme/openstack : inventaire/multinode.3-controleurs.exemple (osctl02, osctl03)" \
  _m10p_fichier_contient plateforme/openstack inventaire/multinode.3-controleurs.exemple 'osctl02' 'osctl03'

title "Ménage"
check_cmd "plus aucune instance ha-essai*" _m10p_aucune_instance ha-essai
