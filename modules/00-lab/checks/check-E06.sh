# shellcheck shell=bash
# M00-E06 — Préparer pve01 (dépôts, mises à jour, virtualisation imbriquée).
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).

title "M00-E06 — Préparer pve01"

# Code retour 1 si une strophe deb822 ou une ligne .list active pointe vers enterprise.proxmox.com
NO_ENTERPRISE="perl -00 -ne 'if (/^URIs:.*enterprise\.proxmox\.com/m && !/^Enabled:\s*no\s*\$/mi) { \$f = 1 } END { exit(\$f ? 1 : 0) }' /etc/apt/sources.list.d/*.sources 2>/dev/null \
  && ! grep -hEqs '^[[:space:]]*deb[[:space:]].*enterprise\.proxmox\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.list"

if remote "$WB_PVE_HOST" "pveversion | grep -q '^pve-manager/9\.'" >/dev/null 2>&1; then
  check_ssh_output "Proxmox VE en version 9.x" "$WB_PVE_HOST" '^pve-manager/9\.' "pveversion"
else
  skip "Proxmox VE en version 9.x" "pve01 n'est pas en 9.x : le plan de montée de version s'applique"
fi

if remote "$WB_PVE_HOST" "pvesubscription get 2>/dev/null | grep -Eqi '^status: *active'" >/dev/null 2>&1; then
  skip "aucun dépôt enterprise actif" "abonnement actif : le dépôt enterprise est légitime"
  check_ssh_output "dépôt pve-enterprise connu d'APT" "$WB_PVE_HOST" \
    'enterprise\.proxmox\.com/debian/pve [a-z]+/pve-enterprise' "apt-cache policy"
else
  check_ssh "aucun dépôt enterprise actif sans abonnement" "$WB_PVE_HOST" "$NO_ENTERPRISE"
  check_ssh_output "dépôt pve-no-subscription connu d'APT" "$WB_PVE_HOST" \
    'download\.proxmox\.com/debian/pve [a-z]+/pve-no-subscription' "apt-cache policy"
fi

check_ssh "index APT rafraîchis il y a moins de 7 jours" "$WB_PVE_HOST" \
  "find /var/lib/apt/lists -maxdepth 1 -name '*_Packages' -mtime -7 | grep -q ."
check_ssh "le nom du nœud se résout vers une adresse non loopback" "$WB_PVE_HOST" \
  "a=\$(getent ahostsv4 \"\$(hostname)\" | awk 'NR==1 {print \$1}'); test -n \"\$a\" && case \"\$a\" in 127.*) false ;; *) true ;; esac"
check_ssh "le CPU expose VT-x (drapeau vmx)" "$WB_PVE_HOST" "grep -qw vmx /proc/cpuinfo"
check_ssh_output "virtualisation imbriquée active (kvm_intel nested)" "$WB_PVE_HOST" '^(Y|1)$' \
  "cat /sys/module/kvm_intel/parameters/nested"
check_ssh "virtualisation imbriquée persistante dans /etc/modprobe.d/" "$WB_PVE_HOST" \
  "grep -rhEqs '^[[:space:]]*options[[:space:]]+kvm[-_]intel([[:space:]].*)?[[:space:]]nested=(1|Y|y)' /etc/modprobe.d/"
check_ssh "chrony actif sur pve01" "$WB_PVE_HOST" "systemctl is-active --quiet chrony"
