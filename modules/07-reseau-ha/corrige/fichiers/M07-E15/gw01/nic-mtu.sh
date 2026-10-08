#!/usr/bin/env bash
# nic-mtu.sh — M07-E15 (CHG-825) : carte trunk de gw01 (net1, sur vmbr1) en MTU 9000.
# À lancer EN ROOT sur pve01, dans la fenêtre du changement, APRÈS l'instantané de gw01 et la
# modification de /etc/network/interfaces de gw01 (mtu écrit sur ens19 et chaque sous-interface).
# Garde l'adresse MAC existante (sinon l'invité verrait une nouvelle carte).
#
# Usage : ./nic-mtu.sh [--annuler] [--avec-redemarrage]
#
# ⚠️ Un changement de MTU d'une carte virtio n'est pas appliqué en place : si l'option « hotplug »
# de la VM contient « network » (c'est le défaut de Proxmox), Proxmox DÉBRANCHE puis REBRANCHE la
# carte à chaud : ens19 et toutes ses sous-interfaces tombent (tout le lab coupé, VPN compris) et
# ifupdown ne les remonte pas forcément. Le script refuse donc ce cas, sauf --avec-redemarrage :
# arrêt propre de gw01, changement, redémarrage (coupure maîtrisée d'une à deux minutes, la
# configuration de gw01 est relue entière au démarrage).
set -euo pipefail

vmid=1000
mtu=9000
redemarrer=0
for a in "$@"; do
  case "$a" in
    --annuler) mtu=1500 ;;
    --avec-redemarrage) redemarrer=1 ;;
    *) echo "Usage : $0 [--annuler] [--avec-redemarrage]" >&2; exit 2 ;;
  esac
done

actuel="$(qm config "$vmid" | sed -n 's/^net1: //p')"
[[ -n "$actuel" ]] || { echo "net1 introuvable sur la VM $vmid" >&2; exit 1; }
echo "avant : net1: $actuel"
# Remplace (ou ajoute) l'option mtu=, garde tout le reste (modèle=MAC, bridge, firewall…).
nouveau="$(sed -E 's/(^|,)mtu=[0-9]+//' <<<"$actuel"),mtu=$mtu"
if [[ "$nouveau" == "$actuel" ]]; then
  echo "net1 déjà en mtu=$mtu : rien à faire."
  exit 0
fi

en_marche=0
qm status "$vmid" | grep -q 'status: running' && en_marche=1
hotplug="$(qm config "$vmid" | sed -n 's/^hotplug: //p')"
hotplug="${hotplug:-network,disk,usb}"   # valeur par défaut de Proxmox quand l'option est absente
reseau_a_chaud=0
[[ "$hotplug" == 1 || ",$hotplug," == *,network,* ]] && reseau_a_chaud=1

if ((en_marche && reseau_a_chaud && !redemarrer)); then
  cat >&2 <<FIN
gw01 tourne et son hotplug ($hotplug) contient « network » : le changement serait appliqué À CHAUD
(carte débranchée puis rebranchée, tout le lab coupé, remontée des interfaces non garantie).
Relance avec --avec-redemarrage dans la fenêtre du changement (console vérifiée : qm terminal $vmid).
FIN
  exit 1
fi

if ((en_marche && redemarrer)); then
  echo "Arrêt propre de gw01 (coupure du lab jusqu'au redémarrage)…"
  qm shutdown "$vmid" --timeout 120
fi
qm set "$vmid" --net1 "$nouveau"
echo "après : $(qm config "$vmid" | sed -n 's/^net1: /net1: /p')"
if ((en_marche && redemarrer)); then
  qm start "$vmid"
  echo "gw01 redémarre : vérifie depuis la console (qm terminal $vmid) que ens19 et ses sous-interfaces sont UP,"
  echo "puis les MTU : ip -br link | grep ens19"
else
  qm pending "$vmid" | grep -E 'net1' || true
fi
