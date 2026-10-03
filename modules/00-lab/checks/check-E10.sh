# shellcheck shell=bash
# M00-E10 — Construire le routeur/pare-feu gw01.
# Lecture seule. Configuration de la VM lue sur pve01 (WB_PVE_HOST) ; contrôles internes
# exécutés sur gw01 via l'alias SSH « gw01 » (utilisateur admin, sudo -n).

title "M00-E10 — Construire le routeur/pare-feu gw01"

VLANS_ROUTES="10 20 30 40 50 52 60 70 99"

# Commande distante : code 0 si la ressource VM <vmid> a <champ> égal à <valeur> (/cluster/resources)
_m00_vm() {
  printf "pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{vmid} == %d && (\$_->{%s} // q{}) eq q{%s} } @{decode_json(\$_)})'" "$1" "$2" "$3"
}

# --- La VM vue depuis l'hyperviseur ---------------------------------------------
check_ssh "la VM 1000 s'appelle gw01" "$WB_PVE_HOST" "$(_m00_vm 1000 name gw01)"
check_ssh "gw01 est dans le pool lab" "$WB_PVE_HOST" "$(_m00_vm 1000 pool lab)"
check_ssh "gw01 est démarrée" "$WB_PVE_HOST" "$(_m00_vm 1000 status running)"
check_ssh_output "gw01 démarre avec pve01 (onboot)" "$WB_PVE_HOST" '^onboot: 1' "qm config 1000"
check_ssh_output "net0 de gw01 est sur vmbr0" "$WB_PVE_HOST" '^net0: .*bridge=vmbr0(,|$)' "qm config 1000"
check_ssh "net1 de gw01 est sur vmbr1, sans tag (trunk)" "$WB_PVE_HOST" \
  "qm config 1000 | grep -E '^net1: .*bridge=vmbr1(,|\$)' | grep -vq 'tag='"
check_ssh "l'agent QEMU de gw01 répond" "$WB_PVE_HOST" "qm guest cmd 1000 ping"

# --- Accès de pve01 au lab ------------------------------------------------------
check_ssh_output "pve01 a une route vers 10.10.0.0/16 via une passerelle sur vmbr0" "$WB_PVE_HOST" \
  '^10\.10\.0\.0/16 via ([0-9]+\.){3}[0-9]+ dev vmbr0' "ip -4 route show 10.10.0.0/16"
check_ssh "la route vers 10.10.0.0/16 est persistante sur pve01" "$WB_PVE_HOST" \
  "grep -Eq '^[^#]*10\.10\.0\.0/16' /etc/network/interfaces"
check_ping "10.10.10.1 (gw01, VLAN MGMT) répond" 10.10.10.1
check_ping "10.10.99.1 (gw01, VLAN SANDBOX) répond" 10.10.99.1

# --- Contrôles internes à gw01 ---------------------------------------------------
if remote gw01 true >/dev/null 2>&1; then
  check_ssh "connexion SSH à gw01 (alias gw01)" gw01 true
  check_ssh_output "nom d'hôte gw01" gw01 '^gw01$' "hostname -s"
  check_ssh "sudo sans mot de passe pour admin" gw01 "sudo -n true"
  check_ssh_output "authentification SSH par mot de passe refusée" gw01 '^passwordauthentication no' \
    "sudo -n sshd -T 2>/dev/null"
  check_ssh_output "ens18 (WAN) a une adresse IPv4" gw01 \
    '[[:space:]]UP[[:space:]]+([0-9]+\.){3}[0-9]+/' "ip -4 -br addr show dev ens18"
  for v in $VLANS_ROUTES; do
    check_ssh_output "ens19.$v est UP et porte 10.10.$v.1/24" gw01 \
      "[[:space:]]UP[[:space:]].*10\.10\.$v\.1/24" "ip -4 -br addr show dev ens19.$v"
  done
  check_ssh "les neuf sous-interfaces sont déclarées dans /etc/network/interfaces" gw01 \
    "for v in $VLANS_ROUTES; do grep -rEqs \"^[[:space:]]*iface[[:space:]]+ens19\.\$v[[:space:]]\" /etc/network/interfaces /etc/network/interfaces.d/ || exit 1; done"
  check_ssh "aucune interface pour les VLANs non routés 31, 32, 41, 51" gw01 \
    "for v in 31 32 41 51; do ip link show dev ens19.\$v >/dev/null 2>&1 && exit 1; done; true"
  check_ssh_output "routage IPv4 actif" gw01 '^1$' "sysctl -n net.ipv4.ip_forward"
  check_ssh "routage IPv4 persistant dans /etc/sysctl.d/99-routeur.conf" gw01 \
    "grep -Eq '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1' /etc/sysctl.d/99-routeur.conf"
  check_ssh "service nftables activé au démarrage" gw01 "systemctl is-enabled --quiet nftables"
  check_ssh "service nftables actif" gw01 "systemctl is-active --quiet nftables"
  check_ssh "/etc/nftables.conf est syntaxiquement valide" gw01 "sudo -n nft -c -f /etc/nftables.conf"
  check_ssh_output "table inet filter chargée" gw01 '^table inet filter' "sudo -n nft list tables"
  check_ssh_output "table ip nat chargée" gw01 '^table ip nat' "sudo -n nft list tables"
  check_ssh_output "politique drop sur la chaîne input" gw01 'hook input priority [^;]+; policy drop;' \
    "sudo -n nft list chain inet filter input"
  check_ssh_output "politique drop sur la chaîne forward" gw01 'hook forward priority [^;]+; policy drop;' \
    "sudo -n nft list chain inet filter forward"
  check_ssh_output "traduction masquerade en sortie de ens18" gw01 'oif(name)? "ens18".*masquerade' \
    "sudo -n nft list chain ip nat postrouting"
  check_ssh "gw01 joint Internet (deb.debian.org, TCP 443)" gw01 \
    "timeout 5 bash -c '</dev/tcp/deb.debian.org/443'"
else
  check_ssh "connexion SSH à gw01 (alias gw01)" gw01 true
  skip "contrôles internes à gw01" "connexion SSH impossible"
fi
