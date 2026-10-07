#!/usr/bin/env bash
# tests/tester-image.sh — test automatique d'un template d'image (M03-E10, complété en M03-E14).
#
# Usage : tests/tester-image.sh [--junit FICHIER] [--garder] <VMID-template>
#   Clone DEUX fois le template (clones liés, VMID libres de 2030-2033, pool lab, étiquette
#   env-m03, VNet vsandbox en DHCP, utilisateur cloud-init admin + clé SSH éphémère), les
#   démarre, attend l'agent QEMU et SSH, puis vérifie le premier démarrage, l'identité unique
#   des clones, le temps, sshd, la CA, les mises à jour et le durcissement (SEC-450).
#   Les deux VMs sont TOUJOURS détruites à la fin (--garder : conservées en cas d'échec).
#   --junit FICHIER : rapport JUnit (affiché par GitLab dans l'onglet « Tests » du pipeline).
# Codes retour : 0 image conforme · 1 test en échec · 2 usage · 3 refus d'un garde-fou
# Accès : outils/pve.sh (jeton wb-packer@pve!packer) ; aucune clé de ce poste n'est utilisée.
# shellcheck disable=SC2154  # PKR_VAR_proxmox_* : chargées par pve_charger_acces (outils/pve.sh)
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées dans la VM de test
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null  # outils/pve.sh du projet
. "$racine/outils/pve.sh"

usage() { sed -n '4,13s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }
junit=""
garder=0
while (($#)); do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --junit) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; junit="$2"; shift 2 ;;
    --garder) garder=1; shift ;;
    -*) usage >&2; exit 2 ;;
    *) break ;;
  esac
done
case "${1:-}" in
  "" | *[!0-9]*) usage >&2; exit 2 ;;
esac
tpl="$1"
for c in curl jq ssh ssh-keygen; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done
pve_charger_acces
noeud="$PKR_VAR_proxmox_node"
echec() { echo "ÉCHEC : $*" >&2; exit 1; }
refus() { echo "REFUS : $*" >&2; exit 3; }

conf_tpl="$(pve_api GET "/nodes/$noeud/qemu/$tpl/config")" || echec "template $tpl illisible"
[[ "$(jq -r '.template // 0' <<<"$conf_tpl")" == 1 ]] || refus "$tpl n'est pas un template"
nom_tpl="$(jq -r '.name' <<<"$conf_tpl")"

# --- Clé SSH éphémère : le test ne dépend ni de adm01 ni d'un secret de la CI -------------
tmp="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C "tester-image@$tpl" -f "$tmp/cle"
cle_enc="$(jq -rn --arg k "$(cat "$tmp/cle.pub")" '$k | @uri')"

declare -a vms=() noms=() ips=()
# shellcheck disable=SC2329  # appelée par le piège EXIT
nettoyer() {
  local rc=$? i conf upid
  if ((garder && rc != 0)); then
    echo "VMs conservées pour analyse : ${vms[*]:-aucune} (clé : $tmp/cle). À détruire ensuite." >&2
    return
  fi
  for i in "${!vms[@]}"; do
    conf="$(pve_api GET "/nodes/$noeud/qemu/${vms[$i]}/config" 2>/dev/null)" || continue
    # Garde-fou : on ne détruit que ce que ce script a créé (nom attendu).
    [[ "$(jq -r '.name' <<<"$conf")" == "${noms[$i]}" ]] || { echo "VM ${vms[$i]} inattendue : non détruite" >&2; continue; }
    upid="$(pve_api POST "/nodes/$noeud/qemu/${vms[$i]}/status/stop" 2>/dev/null)" \
      && pve_attendre_tache "$(jq -r . <<<"$upid")" 120 || true
    upid="$(pve_api DELETE "/nodes/$noeud/qemu/${vms[$i]}" purge=1 destroy-unreferenced-disks=1)" \
      && pve_attendre_tache "$(jq -r . <<<"$upid")" 300 && echo "VM de test ${vms[$i]} détruite"
  done
  rm -rf -- "$tmp"
}
trap nettoyer EXIT

# --- 1. Deux clones liés ------------------------------------------------------------------
for suffixe in a b; do
  nom="m03-test-$tpl-$suffixe"
  vmid=""
  # Le premier VMID libre peut être pris entre le test et le clonage (autre test en cours) :
  # on retente sur le suivant.
  for essai in 1 2 3 4; do
    vmid="$(pve_premier_libre 2030 2033)" || echec "aucun VMID libre dans 2030-2033 (VMs de test oubliées ?)"
    if upid="$(pve_api POST "/nodes/$noeud/qemu/$tpl/clone" "newid=$vmid" "name=$nom" pool=lab full=0)"; then
      break
    fi
    ((essai < 4)) || echec "clonage refusé"
    sleep 3
  done
  vms+=("$vmid"); noms+=("$nom")
  pve_attendre_tache "$(jq -r . <<<"$upid")" 300 || echec "clonage $tpl → $vmid en échec"
  # ciupgrade=0 : on teste l'image telle qu'elle est, pas une mise à jour faite au démarrage.
  pve_api PUT "/nodes/$noeud/qemu/$vmid/config" tags=env-m03 "net0=virtio,bridge=vsandbox" \
    "ipconfig0=ip=dhcp" ciuser=admin "sshkeys=$cle_enc" ciupgrade=0 \
    nameserver=10.10.20.10 searchdomain=par1.medisphere.internal >/dev/null || echec "configuration de $vmid refusée"
  echo "== Clone lié $tpl ($nom_tpl) → $vmid ($nom)"
done
for vmid in "${vms[@]}"; do
  upid="$(pve_api POST "/nodes/$noeud/qemu/$vmid/status/start")" || echec "démarrage de $vmid refusé"
  pve_attendre_tache "$(jq -r . <<<"$upid")" 120 || echec "démarrage de $vmid en échec"
done

# --- 2. Agent et adresse ------------------------------------------------------------------
adresse() { # adresse VMID — première IPv4 du VLAN 99 vue par l'agent
  pve_api GET "/nodes/$noeud/qemu/$1/agent/network-get-interfaces" 2>/dev/null | jq -r '
    [.result[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4")
     | ."ip-address" | select(startswith("10.10.99."))] | first // empty' || true
}
for vmid in "${vms[@]}"; do
  ip=""
  for _ in $(seq 1 60); do
    ip="$(adresse "$vmid")"
    [[ -n "$ip" ]] && break
    sleep 5
  done
  [[ -n "$ip" ]] || echec "VM $vmid : agent QEMU muet ou pas d'adresse sur vsandbox après 5 min"
  ips+=("$ip")
  echo "VM $vmid : $ip"
done

# known_hosts propre au test : les clés d'hôte sont neuves, on les apprend à la première
# connexion (accept-new) et on vérifie ensuite qu'elles sont uniques. ControlPath=none :
# pas de réutilisation d'une connexion multiplexée vers une adresse déjà vue (M00-E15).
ssh_vm() { # ssh_vm IP commande
  local ip="$1"; shift
  ssh -i "$tmp/cle" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 \
    -o ControlPath=none -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$tmp/known_hosts" -o LogLevel=ERROR "admin@$ip" \
    "PATH=\$PATH:/usr/sbin:/sbin; $*" # sysctl, modprobe… sont dans sbin (hors PATH d'admin sur Debian)
}
for ip in "${ips[@]}"; do
  for _ in $(seq 1 30); do ssh_vm "$ip" true 2>/dev/null && break; sleep 5; done
done

# --- 3. Contrôles -------------------------------------------------------------------------
resultats=() # « statut<TAB>nom<TAB>détail »
ko=0
note() { # note OK|KO "nom" ["détail"]
  resultats+=("$1"$'\t'"$2"$'\t'"${3:-}")
  printf '  [%s] %s%s\n' "$1" "$2" "${3:+ — $3}"
  [[ "$1" == OK ]] || ko=1
}
controle() { # controle "nom" IP 'commande distante' — OK si la commande renvoie 0
  local sortie
  if sortie="$(ssh_vm "$2" "$3" 2>&1)"; then note OK "$1"; else note KO "$1" "$(tail -n 1 <<<"$sortie")"; fi
}
valeur() { ssh_vm "$1" "$2" 2>/dev/null || true; }

ip_a="${ips[0]}"
famille="$(valeur "$ip_a" '. /etc/os-release; echo "$ID"')"
echo "== Contrôles ($nom_tpl, famille $famille)"

for i in 0 1; do
  ip="${ips[$i]}" v="${vms[$i]}"
  controle "$v : connexion SSH par clé (utilisateur cloud-init admin)" "$ip" true
  # Code 0 seulement : 2 = avertissements (clé dépréciée, module en erreur récupérable).
  controle "$v : cloud-init status done, sans erreur ni avertissement" "$ip" 'cloud-init status --wait >/dev/null'
  controle "$v : nom d'hôte = nom de la VM (meta/user-data appliquées)" "$ip" "[ \"\$(hostname)\" = '${noms[$i]}' ]"
  controle "$v : sudo sans mot de passe" "$ip" 'sudo -n true'
  controle "$v : agent QEMU actif" "$ip" 'systemctl is-active -q qemu-guest-agent'
done

# Identité : propre à chaque clone, générée à SON premier démarrage
mid_a="$(valeur "${ips[0]}" 'cat /etc/machine-id')"
mid_b="$(valeur "${ips[1]}" 'cat /etc/machine-id')"
if [[ "$mid_a" =~ ^[0-9a-f]{32}$ && "$mid_b" =~ ^[0-9a-f]{32}$ && "$mid_a" != "$mid_b" ]]; then
  note OK "machine-id initialisés et différents d'un clone à l'autre"
else
  note KO "machine-id initialisés et différents d'un clone à l'autre" "${mid_a:-?} / ${mid_b:-?}"
fi
empreinte='ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | cut -d" " -f2'
cle_a="$(valeur "${ips[0]}" "$empreinte")"
cle_b="$(valeur "${ips[1]}" "$empreinte")"
if [[ -n "$cle_a" && -n "$cle_b" && "$cle_a" != "$cle_b" ]]; then
  note OK "clés d'hôte SSH différentes d'un clone à l'autre"
else
  note KO "clés d'hôte SSH différentes d'un clone à l'autre" "${cle_a:-?} / ${cle_b:-?}"
fi
controle "clés d'hôte générées au premier démarrage du clone (pas héritées du template)" "$ip_a" \
  '[ "$(stat -c %Y /etc/ssh/ssh_host_ed25519_key)" -ge "$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) - 5 ))" ]'
if [[ "${ips[0]}" != "${ips[1]}" ]]; then
  note OK "adresses DHCP différentes (${ips[0]}, ${ips[1]})"
else
  note KO "adresses DHCP différentes" "même adresse ${ips[0]} : identifiant DHCP partagé ?"
fi
controle "compte de construction absent (packer)" "$ip_a" '! id packer >/dev/null 2>&1'
controle "aucun historique de shell hérité du build" "$ip_a" 'sudo -n sh -c "! test -s /root/.bash_history"'

# Temps : chrony synchronisé sur la passerelle du VLAN (règle du lab, PLAN §4.3 bis)
controle "chrony synchronisé sur la passerelle du VLAN" "$ip_a" \
  'gw=$(ip -4 route show default | awk "{print \$3; exit}"); chronyc waitsync 12 >/dev/null 2>&1; chronyc -n sources | grep -Eq "^\^\*[[:space:]]+$gw[[:space:]]"'

# Réseau et confiance
controle "résolution DNS du lab (git01.par1.medisphere.internal)" "$ip_a" 'getent hosts git01.par1.medisphere.internal >/dev/null'
if [[ "$famille" == rocky ]]; then
  ca=/etc/pki/ca-trust/source/anchors/medisphere-provisoire.crt magasin=/etc/pki/tls/certs/ca-bundle.crt
else
  ca=/usr/local/share/ca-certificates/medisphere-provisoire.crt magasin=/etc/ssl/certs/ca-certificates.crt
fi
controle "CA provisoire MédiSphère dans le magasin système" "$ip_a" "openssl verify -CAfile $magasin $ca >/dev/null"

# sshd effectif (E09) et durcissement (E13, SEC-450)
sshd_t="$(valeur "$ip_a" 'sudo -n sshd -T')"
for attendu in 'permitrootlogin no' 'passwordauthentication no' 'x11forwarding no' \
  'allowagentforwarding no' 'maxauthtries 3'; do
  if grep -qx "$attendu" <<<"$sshd_t"; then note OK "sshd -T : $attendu"; else note KO "sshd -T : $attendu"; fi
done
if [[ -n "$sshd_t" ]] && ! grep -Eq '^(macs|kexalgorithms|ciphers) .*(sha1|cbc)' <<<"$sshd_t"; then
  note OK "sshd -T : ni SHA-1 ni CBC"
else
  note KO "sshd -T : ni SHA-1 ni CBC"
fi
controle "noyau : redirections ICMP refusées, martiens journalisés" "$ip_a" \
  '[ "$(sysctl -n net.ipv4.conf.all.accept_redirects)$(sysctl -n net.ipv4.conf.all.log_martians)" = 01 ]'
controle "modules interdits non chargeables (sctp, usb-storage)" "$ip_a" \
  'for m in sctp usb-storage; do modprobe -n -v $m 2>&1 | grep -Eq "^install /(usr/)?bin/false" || exit 1; done'
controle "auditd actif" "$ip_a" 'systemctl is-active -q auditd'
controle "aucun port TCP en écoute hors SSH" "$ip_a" \
  '! ss -Htln | awk "{print \$4}" | grep -Ev "^(127\.[0-9.]+(%[a-z0-9]+)?|\[::1\]):[0-9]+$" | grep -Ev ":22$" | grep -q .'

# Exploitation
controle "journal persistant (/var/log/journal)" "$ip_a" 'test -d /var/log/journal'
if [[ "$famille" == rocky ]]; then
  controle "correctifs automatiques (dnf-automatic.timer)" "$ip_a" 'systemctl is-enabled -q dnf-automatic.timer'
  controle "SELinux en mode enforcing" "$ip_a" '[ "$(getenforce)" = Enforcing ]'
else
  controle "correctifs de sécurité automatiques (unattended-upgrades)" "$ip_a" \
    'apt-config dump | grep -q "^APT::Periodic::Unattended-Upgrade \"1\";"'
fi

# --- 4. Rapport ----------------------------------------------------------------------------
if [[ -n "$junit" ]]; then
  xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<<"$1"; }
  mkdir -p "$(dirname "$junit")"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    printf '<testsuite name="tester-image %s" tests="%d" failures="%d">\n' \
      "$(xml "$nom_tpl")" "${#resultats[@]}" "$(printf '%s\n' "${resultats[@]}" | grep -c '^KO' || true)"
    for r in "${resultats[@]}"; do
      IFS=$'\t' read -r statut nom detail <<<"$r"
      printf '  <testcase classname="image.%s" name="%s">' "$(xml "$nom_tpl")" "$(xml "$nom")"
      [[ "$statut" == OK ]] || printf '<failure message="%s"/>' "$(xml "${detail:-échec}")"
      echo '</testcase>'
    done
    echo '</testsuite>'
  } >"$junit"
fi

if ((ko)); then
  echo "== $nom_tpl : NON CONFORME" >&2
  exit 1
fi
echo "== $nom_tpl : conforme"
