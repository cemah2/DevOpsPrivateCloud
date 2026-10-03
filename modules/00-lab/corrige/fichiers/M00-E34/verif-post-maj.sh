#!/usr/bin/env bash
# verif-post-maj.sh — Liste de contrôle après mise à jour de pve01 (M00-E34, CHG-134).
# Lecture seule. À lancer sur pve01 en root ; chaque ligne affiche OK / KO / INFO.
set -uo pipefail

ok()   { printf '  [OK]   %s\n' "$1"; }
ko()   { printf '  [KO]   %s\n' "$1"; ECHECS=$((ECHECS + 1)); }
info() { printf '  [INFO] %s\n' "$1"; }
ECHECS=0

echo "== Versions"
info "noyau en service : $(uname -r)"
info "$(pveversion)"
dernier="$(find /lib/modules -mindepth 1 -maxdepth 1 -name '*-pve' -printf '%f\n' | sort -V | tail -n 1)"
if [[ "$(uname -r)" == "$dernier" ]]; then ok "noyau le plus récent installé"; else
  info "noyau le plus récent installé : $dernier (épinglé ? voir proxmox-boot-tool kernel list)"; fi

echo "== Paquets"
if LC_ALL=C apt-get -s -o Debug::NoLocking=1 dist-upgrade | grep -Eq '^0 upgraded, 0 newly installed'; then
  ok "aucune mise à jour en attente"; else ko "mises à jour encore en attente"; fi
if dpkg --audit | grep -q .; then ko "paquets mal configurés (dpkg --audit)"; else ok "dpkg cohérent"; fi

echo "== Services"
if systemctl --failed --no-legend --plain | grep -q .; then
  ko "services en échec : $(systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd' ' -)"
else ok "aucun service en échec"; fi
for s in pve-cluster pvedaemon pveproxy pvestatd pve-firewall pvescheduler chrony; do
  if systemctl is-active --quiet "$s"; then ok "$s actif"; else ko "$s inactif"; fi
done

echo "== Stockages"
while read -r nom type statut _; do
  [[ "$nom" == "Name" ]] && continue
  if [[ "$statut" == "active" ]]; then ok "stockage $nom ($type) actif"; else ko "stockage $nom ($type) : $statut"; fi
done < <(pvesm status 2>/dev/null)

echo "== Réseau et pare-feu"
if pve-firewall status | grep -q 'enabled/running'; then ok "pare-feu actif"; else ko "pare-feu non actif"; fi
for b in vmbr0 vmbr1 vinfra vmgmt; do
  if ip link show dev "$b" 2>/dev/null | grep -q 'state UP'; then ok "$b UP"; else ko "$b absent ou DOWN"; fi
done

echo "== Socle"
for v in 1000 1002 1001; do
  if qm status "$v" 2>/dev/null | grep -q running; then ok "VM $v en marche"; else ko "VM $v arrêtée"; fi
done
if ping -c 2 -W 2 10.10.20.10 >/dev/null 2>&1; then ok "dns01 joignable depuis pve01"; else ko "dns01 injoignable"; fi
if ping -c 2 -W 2 10.20.10.10 >/dev/null 2>&1; then ok "pbs01 joignable via le tunnel"; else ko "pbs01 injoignable"; fi

echo "== Journal du démarrage (erreurs)"
n="$(journalctl -b -p err --no-pager -q | wc -l)"
info "$n ligne(s) de niveau err depuis le démarrage (journalctl -b -p err)"

echo
if (( ECHECS == 0 )); then echo "Bilan : tout est vert."; else echo "Bilan : $ECHECS point(s) à traiter."; fi
exit $(( ECHECS > 0 ))
