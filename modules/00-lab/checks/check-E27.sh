# shellcheck shell=bash
# Vérification M00-E27 — Durcir l'accès à pve01 (lancé depuis adm01).

title "M00-E27 — Durcir l'accès à pve01"
require_cmd ssh

PVE_FQDN="pve01.par1.medisphere.internal"

# --- Second facteur -------------------------------------------------------
check_ssh_output "root@pam possède un TOTP" "$WB_PVE_HOST" '"type" *: *"totp"' \
  "pvesh get /access/tfa/root@pam --output-format json"
check_ssh_output "root@pam possède des clés de récupération" "$WB_PVE_HOST" '"type" *: *"recovery"' \
  "pvesh get /access/tfa/root@pam --output-format json"
check_ssh_output "wb-admin@pve possède un TOTP" "$WB_PVE_HOST" '"type" *: *"totp"' \
  "pvesh get /access/tfa/wb-admin@pve --output-format json"
check_ssh_output "wb-admin@pve possède des clés de récupération" "$WB_PVE_HOST" '"type" *: *"recovery"' \
  "pvesh get /access/tfa/wb-admin@pve --output-format json"

# --- SSH ------------------------------------------------------------------
check_ssh_output "sshd de pve01 : root uniquement par clé" "$WB_PVE_HOST" \
  '^permitrootlogin (prohibit-password|without-password)$' "sshd -T 2>/dev/null"
check_ssh_output "sshd de pve01 : authentification par mot de passe désactivée" "$WB_PVE_HOST" \
  '^passwordauthentication no$' "sshd -T 2>/dev/null"
check_ssh_output "sshd de pve01 : keyboard-interactive désactivé" "$WB_PVE_HOST" \
  '^kbdinteractiveauthentication no$' "sshd -T 2>/dev/null"
# shellcheck disable=SC2086  # WB_SSH_OPTS doit être découpé en mots
check_output "pve01 refuse une connexion SSH sans clé" 'Permission denied \(publickey\)' \
  ssh -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o PubkeyAuthentication=no -o ConnectTimeout="$WB_TIMEOUT" $WB_SSH_OPTS "$WB_PVE_HOST" true
check_ssh "pve01 accepte une connexion SSH par clé depuis adm01" "$WB_PVE_HOST" "true"

# --- Pare-feu -------------------------------------------------------------
check_ssh_output "le pare-feu de pve01 est actif" "$WB_PVE_HOST" 'enabled/running' "pve-firewall status"
check_ssh_output "pare-feu datacenter activé" "$WB_PVE_HOST" '"enable" *: *1' \
  "pvesh get /cluster/firewall/options --output-format json"
check_ssh_output "IPSet management : réseau du VPN d'administration présent" "$WB_PVE_HOST" '10\.255\.1\.0/24' \
  "pvesh get /cluster/firewall/ipset/management --output-format json"
check_ssh_output "IPSet management : réseau MGMT présent" "$WB_PVE_HOST" '10\.10\.10\.0/24' \
  "pvesh get /cluster/firewall/ipset/management --output-format json"
if [[ -n "${WB_LAN_MAISON:-}" ]]; then
  check_ssh_output "IPSet management : LAN maison présent" "$WB_PVE_HOST" "${WB_LAN_MAISON//./\\.}" \
    "pvesh get /cluster/firewall/ipset/management --output-format json"
else
  skip "IPSet management : LAN maison présent" "WB_LAN_MAISON non défini dans lab/lab.env"
fi
check_ssh "le pare-feu de l'hôte n'est pas désactivé" "$WB_PVE_HOST" \
  "! pvesh get /nodes/\$(hostname)/firewall/options --output-format json | grep -Eq '\"enable\" *: *0'"

# --- Accessibilité depuis adm01 ------------------------------------------
check_port "port 8006 de pve01 joignable depuis adm01" "$PVE_FQDN" 8006
check_port "port 22 de pve01 joignable depuis adm01" "$PVE_FQDN" 22

# --- Pas de pare-feu activé sur les VMs du lab ------------------------------
check_ssh "aucune VM du socle n'a de pare-feu VM activé" "$WB_PVE_HOST" \
  "! grep -sqE '^enable: *1' /etc/pve/firewall/1000.fw /etc/pve/firewall/1001.fw /etc/pve/firewall/1002.fw"
