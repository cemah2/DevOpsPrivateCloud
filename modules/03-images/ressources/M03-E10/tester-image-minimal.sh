#!/usr/bin/env bash
# tests/tester-image.sh — test MINIMAL d'un template (fourni en M03-E10, complété en M03-E14).
#
# Usage : tests/tester-image.sh <VMID-template>
#   Clone le template en clone lié dans le premier VMID libre de 2030-2033 (pool lab,
#   étiquette env-m03, VNet vsandbox en DHCP, utilisateur cloud-init admin + clé de ce poste),
#   le démarre, attend l'agent QEMU, puis vérifie en SSH que cloud-init a terminé sans
#   erreur et que sudo fonctionne. La VM de test est TOUJOURS détruite à la fin.
# Codes retour : 0 image conforme · 1 test en échec · 2 usage
# Accès : outils/pve.sh (jeton wb-packer@pve!packer). Clé publique : $CLE_SSH (défaut ~/.ssh/id_ed25519.pub).
#
# Ce test ne vérifie que l'essentiel (« un clone démarre et est administrable »). M03-E14
# y ajoute l'identité unique (machine-id, clés d'hôte), le temps, sshd, la CA…
# shellcheck disable=SC2154  # PKR_VAR_proxmox_* : chargées par pve_charger_acces (outils/pve.sh)
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null  # outils/pve.sh du projet
. "$racine/outils/pve.sh"

usage() { sed -n '4,9s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "" | *[!0-9]*) usage >&2; exit 2 ;;
esac
tpl="$1"
cle_pub="${CLE_SSH:-$HOME/.ssh/id_ed25519.pub}"
[[ -r "$cle_pub" ]] || { echo "clé publique illisible : $cle_pub" >&2; exit 2; }
pve_charger_acces
noeud="$PKR_VAR_proxmox_node"
nom="m03-test-$tpl"
echec() { echo "ÉCHEC : $*" >&2; exit 1; }

conf_tpl="$(pve_api GET "/nodes/$noeud/qemu/$tpl/config")" || echec "template $tpl illisible"
[[ "$(jq -r '.template // 0' <<<"$conf_tpl")" == 1 ]] || echec "$tpl n'est pas un template"

vmid="$(pve_premier_libre 2030 2033)" || echec "aucun VMID libre dans 2030-2033 (VMs de test oubliées ?)"

# shellcheck disable=SC2329  # appelée par le piège EXIT
nettoyer() {
  local conf
  conf="$(pve_api GET "/nodes/$noeud/qemu/$vmid/config" 2>/dev/null)" || return 0
  # Garde-fou : on ne détruit que ce que ce script a créé.
  [[ "$(jq -r '.name' <<<"$conf")" == "$nom" ]] || { echo "VM $vmid inattendue : non détruite" >&2; return 0; }
  upid="$(pve_api POST "/nodes/$noeud/qemu/$vmid/status/stop" 2>/dev/null)" \
    && pve_attendre_tache "$(jq -r . <<<"$upid")" 120 || true
  upid="$(pve_api DELETE "/nodes/$noeud/qemu/$vmid" purge=1 destroy-unreferenced-disks=1)" \
    && pve_attendre_tache "$(jq -r . <<<"$upid")" 300 && echo "VM de test $vmid détruite"
}
trap nettoyer EXIT

echo "== Clone lié $tpl → $vmid ($nom)"
upid="$(pve_api POST "/nodes/$noeud/qemu/$tpl/clone" "newid=$vmid" "name=$nom" pool=lab full=0)" \
  || echec "clonage refusé"
pve_attendre_tache "$(jq -r . <<<"$upid")" 300 || echec "clonage en échec"

# sshkeys doit être DÉJÀ encodée en URL (piège de l'API, M00-E18), puis encodée à nouveau
# comme paramètre de formulaire par curl.
cle_enc="$(jq -rn --arg k "$(head -n 1 "$cle_pub")" '$k | @uri')"
pve_api PUT "/nodes/$noeud/qemu/$vmid/config" tags=env-m03 "net0=virtio,bridge=vsandbox" \
  "ipconfig0=ip=dhcp" ciuser=admin "sshkeys=$cle_enc" >/dev/null || echec "configuration refusée"
upid="$(pve_api POST "/nodes/$noeud/qemu/$vmid/status/start")" || echec "démarrage refusé"
pve_attendre_tache "$(jq -r . <<<"$upid")" 120 || echec "démarrage en échec"

echo "== Attente de l'agent QEMU et de l'adresse IP"
ip=""
for _ in $(seq 1 60); do
  if pve_api POST "/nodes/$noeud/qemu/$vmid/agent/ping" >/dev/null 2>&1; then
    ip="$(pve_api GET "/nodes/$noeud/qemu/$vmid/agent/network-get-interfaces" 2>/dev/null | jq -r '
      [.result[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4")
       | ."ip-address"] | first // empty')" || true
    [[ -n "$ip" ]] && break
  fi
  sleep 5
done
[[ -n "$ip" ]] || echec "agent QEMU muet ou pas d'adresse IPv4 après 5 min"
echo "VM $vmid : $ip"

# VM éphémère aux clés d'hôte neuves : pas de known_hosts (le test des clés est en M03-E14).
# ControlPath=none : pas de réutilisation d'une connexion multiplexée (ControlMaster d'adm01).
ssh_vm() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlPath=none \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "admin@$ip" "$@"
}
for _ in $(seq 1 30); do ssh_vm true 2>/dev/null && break; sleep 5; done

echo "== Contrôles"
ok=0
controle() { if ssh_vm "$2" >/dev/null 2>&1; then echo "  [OK] $1"; else echo "  [KO] $1"; ok=1; fi; }
controle "connexion SSH par clé (utilisateur cloud-init admin)" true
controle "cloud-init a terminé sans erreur" "cloud-init status --wait"
controle "sudo sans mot de passe" "sudo -n true"
controle "agent QEMU actif" "systemctl is-active --quiet qemu-guest-agent"
exit "$ok"
