#!/usr/bin/env bash
# lb-e16.sh — crée le répartiteur OVN de M10-E16 dans mediagenda-dev (en tant que membre du projet).
# Usage : OS_CLOUD=medisphere-mediagenda-dev outils/lb-e16.sh <paire-de-clés>
# Prérequis : réseau mediagenda-dev-net (M10-E15), greffon python-octaviaclient.
set -euo pipefail
: "${OS_CLOUD:?définis OS_CLOUD (ex. medisphere-mediagenda-dev)}"
cle="${1:?paire de clés SSH}"
ici="$(cd "$(dirname "$0")/.." && pwd)"
sous_reseau=mediagenda-dev-sousreseau
cidr="$(openstack subnet show -f value -c cidr "$sous_reseau")"

openstack security group show e16-web >/dev/null 2>&1 || {
  openstack security group create --description "HTTP depuis le projet et MGMT (M10-E16)" e16-web
  openstack security group rule create --protocol tcp --dst-port 80 --remote-ip "$cidr" e16-web
  openstack security group rule create --protocol tcp --dst-port 80 --remote-ip 10.10.10.0/24 e16-web
}

for n in 1 2; do
  openstack server show "e16-web$n" >/dev/null 2>&1 || openstack server create --wait \
    --image debian-13 --flavor m1.petit --key-name "$cle" --network mediagenda-dev-net \
    --security-group e16-web --security-group mediagenda-dev-admin \
    --user-data "$ici/cloud-init/web-user-data.yaml" "e16-web$n"
done

openstack loadbalancer show lb-e16 >/dev/null 2>&1 || openstack loadbalancer create --wait \
  --name lb-e16 --provider ovn --vip-subnet-id "$sous_reseau"
openstack loadbalancer listener show ecoute-80 >/dev/null 2>&1 || openstack loadbalancer listener create --wait \
  --name ecoute-80 --protocol TCP --protocol-port 80 lb-e16
openstack loadbalancer pool show pool-web >/dev/null 2>&1 || openstack loadbalancer pool create --wait \
  --name pool-web --listener ecoute-80 --protocol TCP --lb-algorithm SOURCE_IP_PORT
for n in 1 2; do
  ip="$(openstack server show -f json "e16-web$n" | jq -r '.addresses["mediagenda-dev-net"][0]')"
  openstack loadbalancer member list -f value -c address pool-web | grep -qx "$ip" || \
    openstack loadbalancer member create --wait --name "e16-web$n" --subnet-id "$sous_reseau" \
      --address "$ip" --protocol-port 80 pool-web
done
[[ -n "$(openstack loadbalancer pool show -f value -c healthmonitor_id pool-web)" ]] || \
  openstack loadbalancer healthmonitor create --wait --name sante-tcp --type TCP \
    --delay 5 --timeout 3 --max-retries 2 pool-web

vip_port="$(openstack loadbalancer show -f value -c vip_port_id lb-e16)"
fip="$(openstack floating ip list --port "$vip_port" -f value -c 'Floating IP Address')"
if [[ -z "$fip" ]]; then
  fip="$(openstack floating ip create -f value -c floating_ip_address ext-net)"
  openstack floating ip set --port "$vip_port" "$fip"
fi
openstack loadbalancer status show lb-e16
echo "IP flottante du répartiteur : $fip"
