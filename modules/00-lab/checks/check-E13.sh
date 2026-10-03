# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E13.sh — M00-E13 : DNS provisoire avec dnsmasq
# Lancé depuis pve01 (avant E15) ou depuis adm01 (après E15). Lecture seule.

title "M00-E13 — DNS provisoire avec dnsmasq"

# Accès aux VMs : alias SSH de adm01 s'ils existent (après E15), sinon accès direct depuis pve01.
h_dns="dns01"
if ! remote dns01 true >/dev/null 2>&1; then h_dns="admin@10.10.20.10"; fi
h_gw="gw01"
if ! remote gw01 true >/dev/null 2>&1; then h_gw="admin@10.10.10.1"; fi
h_adm="adm01"
if ! remote adm01 true >/dev/null 2>&1; then h_adm="admin@10.10.10.10"; fi

# --- Service sur dns01 ---
check_ssh "dns01 : service dnsmasq actif" "$h_dns" \
  'systemctl is-active --quiet dnsmasq'
check_ssh "dns01 : /etc/dnsmasq.d/medisphere.conf présent et non vide" "$h_dns" \
  'test -s /etc/dnsmasq.d/medisphere.conf'
check_ssh "dns01 : le port 53 n'est pas ouvert sur toutes les adresses (écoute ciblée)" "$h_dns" \
  '! ss -Hlnu "sport = :53" | grep -Eq "(0\.0\.0\.0|\*|\[::\]):53"'

# --- Enregistrements A ---
check_ssh_output "A gw01.par1.medisphere.internal → 10.10.10.1" "$h_dns" '^10\.10\.10\.1$' \
  'dig +short +time=3 @10.10.20.10 gw01.par1.medisphere.internal A'
check_ssh_output "A adm01.par1.medisphere.internal → 10.10.10.10" "$h_dns" '^10\.10\.10\.10$' \
  'dig +short +time=3 @10.10.20.10 adm01.par1.medisphere.internal A'
check_ssh_output "A dns01.par1.medisphere.internal → 10.10.20.10" "$h_dns" '^10\.10\.20\.10$' \
  'dig +short +time=3 @10.10.20.10 dns01.par1.medisphere.internal A'
check_ssh_output "A pve01.par1.medisphere.internal → une adresse IPv4" "$h_dns" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  'dig +short +time=3 @10.10.20.10 pve01.par1.medisphere.internal A'
check_ssh_output "A pbs01.par2.medisphere.internal → 10.20.10.10" "$h_dns" '^10\.20\.10\.10$' \
  'dig +short +time=3 @10.10.20.10 pbs01.par2.medisphere.internal A'
check_ssh_output "pbs01.par1.medisphere.internal mène à 10.20.10.10" "$h_dns" '^10\.20\.10\.10$' \
  'dig +short +time=3 @10.10.20.10 pbs01.par1.medisphere.internal A'

# --- Enregistrements PTR ---
check_ssh_output "PTR 10.10.10.1 → gw01.par1.medisphere.internal" "$h_dns" '^gw01\.par1\.medisphere\.internal\.$' \
  'dig +short +time=3 @10.10.20.10 -x 10.10.10.1'
check_ssh_output "PTR 10.10.10.10 → adm01.par1.medisphere.internal" "$h_dns" '^adm01\.par1\.medisphere\.internal\.$' \
  'dig +short +time=3 @10.10.20.10 -x 10.10.10.10'
check_ssh_output "PTR 10.10.20.10 → dns01.par1.medisphere.internal" "$h_dns" '^dns01\.par1\.medisphere\.internal\.$' \
  'dig +short +time=3 @10.10.20.10 -x 10.10.20.10'
check_ssh_output "PTR 10.20.10.10 → pbs01.par2.medisphere.internal" "$h_dns" '^pbs01\.par2\.medisphere\.internal\.$' \
  'dig +short +time=3 @10.10.20.10 -x 10.20.10.10'
check_ssh_output "PTR 10.10.20.1 (passerelle INFRA) → gw01" "$h_dns" '^gw01\.par1\.medisphere\.internal\.$' \
  'dig +short +time=3 @10.10.20.10 -x 10.10.20.1'

# --- Comportement du résolveur ---
check_ssh_output "nom inexistant dans par1 : réponse NXDOMAIN" "$h_dns" 'status: NXDOMAIN' \
  'dig +time=3 @10.10.20.10 nexistepas.par1.medisphere.internal A'
check_ssh_output "reverse privé inconnu (10.10.99.254) : NXDOMAIN local" "$h_dns" 'status: NXDOMAIN' \
  'dig +time=3 @10.10.20.10 -x 10.10.99.254'
check_ssh_output "résolution récursive d'un nom Internet (deb.debian.org)" "$h_dns" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  'dig +short +time=3 @10.10.20.10 deb.debian.org A'

# --- Clients ---
check_ssh_output "adm01 : le nom court « dns01 » se résout (domaine de recherche)" "$h_adm" '^10\.10\.20\.10[[:space:]]' \
  'getent hosts dns01'
check_ssh_output "adm01 : 10.10.10.1 se résout en nom (PTR via le résolveur système)" "$h_adm" 'gw01\.par1\.medisphere\.internal' \
  'getent hosts 10.10.10.1'
check_ssh_output "adm01 : un nom Internet se résout" "$h_adm" '^[0-9a-f.:]+[[:space:]]' \
  'getent hosts deb.debian.org'
check_ssh "adm01 : DNS en TCP vers dns01 possible (inter-VLAN)" "$h_adm" \
  'timeout 3 bash -c "</dev/tcp/10.10.20.10/53"'
check_ssh_output "gw01 : résout les noms du lab" "$h_gw" '^10\.10\.10\.10[[:space:]]' \
  'getent hosts adm01.par1.medisphere.internal'

# --- Bascule des résolveurs (E12 avait posé un résolveur public provisoire) ---
# Résolveurs effectifs d'un hôte (resolvectl si systemd-resolved, sinon resolv.conf),
# hors boucle locale et hors 10.10.20.10 : la liste doit être vide.
_m00_resolveurs_etrangers='{ resolvectl dns 2>/dev/null; grep -E "^nameserver" /etc/resolv.conf; } | grep -oE "([0-9]+\.){3}[0-9]+" | grep -vE "^(127\.|10\.10\.20\.10$)"'
for h in "$h_gw" "$h_adm" "$h_dns"; do
  check_ssh "${h#admin@} : plus aucun résolveur hors 10.10.20.10" "$h" "! $_m00_resolveurs_etrangers"
done
for h in "$h_gw" "$h_adm"; do
  check_ssh "${h#admin@} : le résolveur système est 10.10.20.10" "$h" \
    '{ resolvectl dns 2>/dev/null; cat /etc/resolv.conf; } | grep -q "10\.10\.20\.10"'
done
check_ssh_output "dns01 : le résolveur système résout les noms du lab" "$h_dns" '^10\.10\.10\.10[[:space:]]' \
  'getent hosts adm01.par1.medisphere.internal'
for id in 1001 1002 9000; do
  check_ssh_output "Proxmox : la configuration cloud-init de $id indique le résolveur 10.10.20.10" "$WB_PVE_HOST" \
    '^nameserver: 10\.10\.20\.10$' "qm config $id"
done
