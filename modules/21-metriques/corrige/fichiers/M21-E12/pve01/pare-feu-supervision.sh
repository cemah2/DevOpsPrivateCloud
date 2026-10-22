#!/usr/bin/env bash
# pve01 — IPSet « supervision » et règle d'entrée 8006 et 9100 (M21-E12, PLAT-2212), en root sur pve01.
# ⚠️ Pare-feu DATACENTER : copie de cluster.fw avant, session SSH ouverte pendant l'opération.
# Retour arrière : cp /root/cluster.fw.avant-m21e12 /etc/pve/firewall/cluster.fw && pve-firewall compile
#                  && pve-firewall restart
set -Eeuo pipefail

[[ -e /root/cluster.fw.avant-m21e12 ]] || cp -a /etc/pve/firewall/cluster.fw /root/cluster.fw.avant-m21e12

if ! pvesh get /cluster/firewall/ipset --output-format json | grep -q '"name":"supervision"'; then
  pvesh create /cluster/firewall/ipset --name supervision --comment "Supervision témoin (mon01, M21-E12)"
fi
if ! pvesh get /cluster/firewall/ipset/supervision --output-format json | grep -q '"cidr":"10.10.20.19"'; then
  pvesh create /cluster/firewall/ipset/supervision --cidr 10.10.20.19 --comment mon01
fi
if ! grep -q 'supervision témoin (M21-E12)' /etc/pve/firewall/cluster.fw; then
  pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +supervision --proto tcp \
    --dport 8006,9100 --enable 1 --comment "supervision témoin (M21-E12) : API et node_exporter"
fi
pve-firewall compile | grep -n supervision
