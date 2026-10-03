# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E21.sh — M00-E21 : Tunnel inter-sites PAR1 ↔ PAR2
# À lancer depuis adm01. Lecture seule.

title "M00-E21 — Tunnel inter-sites PAR1 ↔ PAR2"

h_gw="gw01"

# --- Côté PAR1 (gw01) ---
check_ssh "gw01 : wg0 porte 10.255.0.1/30" "$h_gw" \
  'ip -4 -br addr show dev wg0 | grep -q "10\.255\.0\.1/30"'
check_ssh_output "gw01 : wg0 écoute sur UDP 51820" "$h_gw" '^51820$' \
  'sudo -n wg show wg0 listen-port'
check_ssh "gw01 : dernière poignée de main wg0 de moins de 3 minutes" "$h_gw" \
  'sudo -n wg show wg0 latest-handshakes | awk -v now="$(date +%s)" "\$2 > 0 && now - \$2 < 180 {f=1} END {exit !f}"'
check_ssh "gw01 : 10.20.10.10 est routé par wg0" "$h_gw" \
  'ip route get 10.20.10.10 | grep -q "dev wg0"'
check_ssh "gw01 : wg-quick@wg0 activé au démarrage" "$h_gw" \
  'systemctl is-enabled --quiet wg-quick@wg0'

# --- Traversée du tunnel depuis PAR1 ---
check_ping "adm01 → pbs01 (10.20.10.10) par le tunnel" 10.20.10.10
check_port "adm01 → interface web PBS (10.20.10.10:8007)" 10.20.10.10 8007
check_ssh "SSH root sur pbs01 via l'alias $WB_PBS_HOST" "$WB_PBS_HOST" 'true'
check_ssh "pve01 → pbs01:8007 (chemin des sauvegardes)" "$WB_PVE_HOST" \
  'timeout 5 bash -c "</dev/tcp/10.20.10.10/8007"'

# --- Côté PAR2 (pbs01) ---
check_ssh "pbs01 : wg0 porte 10.255.0.2/30" "$WB_PBS_HOST" \
  'ip -4 -br addr show dev wg0 | grep -q "10\.255\.0\.2/30"'
check_ssh "pbs01 : le lab PAR1 (10.10.0.0/16) est routé par wg0" "$WB_PBS_HOST" \
  'ip route get 10.10.10.10 | grep -q "dev wg0"'
check_ssh "pbs01 : vers PAR1, la source est l'adresse de site 10.20.10.10" "$WB_PBS_HOST" \
  'ip route get 10.10.10.10 | grep -q "src 10\.20\.10\.10"'
check_ssh "pbs01 : le VPN d'administration (10.255.1.0/24) est routé par wg0" "$WB_PBS_HOST" \
  'ip route get 10.255.1.2 | grep -q "dev wg0"'
check_ssh "pbs01 : wg-quick@wg0 activé au démarrage" "$WB_PBS_HOST" \
  'systemctl is-enabled --quiet wg-quick@wg0'
check_ssh "pbs01 : pare-feu chargé, politique drop en entrée" "$WB_PBS_HOST" \
  'nft list ruleset | grep -Eq "hook input priority [a-z0-9-]+; policy drop;"'
check_ssh "pbs01 : nftables activé au démarrage" "$WB_PBS_HOST" \
  'systemctl is-enabled --quiet nftables'

# --- Exposition sur le LAN maison ---
if [[ -n "${WB_PBS_LAN:-}" ]]; then
  check_cmd "interface web PBS fermée sur l'adresse LAN de hp01 ($WB_PBS_LAN)" \
    bash -c "! timeout ${WB_TIMEOUT} bash -c '</dev/tcp/${WB_PBS_LAN}/8007' 2>/dev/null"
else
  skip "interface web PBS fermée sur l'adresse LAN de hp01" "WB_PBS_LAN non renseignée dans lab/lab.env"
fi
