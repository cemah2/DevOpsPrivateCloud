#!/usr/bin/env bash
# sdn-lab.sh — Création de la zone SDN « lab » et de ses VNets (M00-E28, PLAT-128).
# À lancer sur pve01, en root. Rejouable : ce qui existe déjà est ignoré.
# N'applique PAS la configuration : relis « pvesh get /cluster/sdn/vnets --pending 1 »
# puis applique avec « pvesh set /cluster/sdn ».
set -euo pipefail

ZONE=lab
BRIDGE=vmbr1

# nom:tag:alias (PLAN.md §4.3 bis)
VNETS=(
  vmgmt:10:MGMT vinfra:20:INFRA vstopub:30:STOR-PUB vstoclu:31:STOR-CLU
  vcoro:32:COROSYNC vk8s:40:K8S vk8slb:41:K8S-LB vosapi:50:OS-API
  vostun:51:OS-TUN vosext:52:OS-EXT vprov:60:PROV vdmz:70:DMZ vsandbox:99:SANDBOX
)

if pvesh get "/cluster/sdn/zones/$ZONE" >/dev/null 2>&1; then
  echo "Zone $ZONE : déjà présente"
else
  pvesh create /cluster/sdn/zones --zone "$ZONE" --type vlan --bridge "$BRIDGE"
  echo "Zone $ZONE : créée (type vlan, bridge $BRIDGE)"
fi

for entree in "${VNETS[@]}"; do
  IFS=: read -r vnet tag alias <<<"$entree"
  if pvesh get "/cluster/sdn/vnets/$vnet" >/dev/null 2>&1; then
    echo "VNet $vnet : déjà présent"
  else
    pvesh create /cluster/sdn/vnets --vnet "$vnet" --zone "$ZONE" --tag "$tag" --alias "$alias"
    echo "VNet $vnet : créé (VLAN $tag, $alias)"
  fi
done

echo
echo "Configuration en attente :"
pvesh get /cluster/sdn/vnets --pending 1 || true
echo
echo "Pour appliquer : pvesh set /cluster/sdn"
