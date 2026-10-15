# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E16.sh — M18-E16 « Cluster API sur OpenStack (facultatif) »
# Lecture seule : manifestes et documentation sur main ; si le profil openstack répond, absence de toute
# ressource « capo-essai » dans le projet plateforme (openstack … list).

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E16 — Cluster API sur OpenStack (facultatif)"
require_cmd jq

check_cmd "plateforme/distributions (main) : manifestes OpenStackCluster sous capi/capo-essai/" \
  _m18p_un_fichier_contient plateforme/distributions capi/capo-essai 'kind: *OpenStackCluster' 'externalNetwork'
check_cmd "capo.md : versions lues au tag, comparaison CAPMOX/CAPO, flux, nettoyage, dérogation mémoire" \
  _m18p_fichier_contient plateforme/medisphere docs/kubernetes/distributions/capo.md \
  'CAPMOX' 'CAPO' 'go\.mod|metadata\.yaml' 'flottante|Octavia' 'nettoyage|supprim' 'm(é|e)moire'

_e16_cloud="${WB_OS_CLOUD_PLATEFORME:-medisphere-plateforme}"
if command -v openstack >/dev/null 2>&1 && timeout 20 openstack --os-cloud "$_e16_cloud" token issue -f value -c id >/dev/null 2>&1; then
  _e16_reste() {
    local t
    for t in "server list" "port list" "floating ip list --long" "security group list" "network list" "loadbalancer list"; do
      # shellcheck disable=SC2086  # sous-commande découpée volontairement
      if timeout 30 openstack --os-cloud "$_e16_cloud" $t -f json 2>/dev/null | jq -e 'tostring | test("capo-essai")' >/dev/null; then
        return 0
      fi
    done
    return 1
  }
  _e16_propre() { ! _e16_reste; }
  check_cmd "projet plateforme : aucune ressource capo-essai restante (serveurs, ports, IP, groupes, réseaux, répartiteurs)" \
    _e16_propre
else
  skip "ressources capo-essai dans le projet plateforme" "profil openstack éteint ou cloud $_e16_cloud injoignable"
fi
