# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M00-E39 « Panne : adm01 ne joint plus dns01 »
#
# Variantes :
#   1. carte réseau de dns01 (net0) déplacée sur le VNet vsandbox (ou tag 99 avant SDN) — pve01 ;
#   2. pare-feu Proxmox activé sur net0 de dns01 (firewall=1) + politique IN DROP au niveau VM,
#      seul le DNS (53) est autorisé — pve01 ;
#   3. masque erroné sur dns01 (10.10.20.10/29 au lieu de /24) : la passerelle n'est plus
#      dans le sous-réseau, la route par défaut disparaît — injecté via l'agent QEMU.
# Sauvegardes : /var/lib/workbook/E39.* sur pve01 (variantes 1, 2) et sur dns01 (variante 3).

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

panne_E39_v1() {
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_DNS01" >/dev/null <<'EOF'
conf="$(qm config "$VMID" | sed -n 's/^net0: //p')"
[ -n "$conf" ] || exit 1
if printf '%s' "$conf" | grep -q 'bridge=vinfra'; then
  neuf="$(printf '%s' "$conf" | sed 's/bridge=vinfra/bridge=vsandbox/')"
elif printf '%s' "$conf" | grep -Eq '(^|,)tag=20(,|$)'; then
  neuf="$(printf '%s' "$conf" | sed -E 's/(^|,)tag=20(,|$)/\1tag=99\2/')"
else
  echo "net0 de $VMID ni sur vinfra ni en tag 20 : état inattendu" >&2; exit 1
fi
[ -f "$WB_DIR/E39.net0" ] || printf '%s\n' "$conf" > "$WB_DIR/E39.net0"
qm set "$VMID" --net0 "$neuf" >/dev/null || exit 1
journal "net0 de la VM $VMID : « $conf » → « $neuf »"
EOF
}

panne_E39_v2() {
  local rc=0
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_DNS01" >/dev/null <<'EOF' || rc=$?
# Le pare-feu de VM n'a d'effet que si le pare-feu du datacenter est actif (E27).
grep -Eq '^[[:space:]]*enable:[[:space:]]*1' /etc/pve/firewall/cluster.fw 2>/dev/null || exit 3
conf="$(qm config "$VMID" | sed -n 's/^net0: //p')"
[ -n "$conf" ] || exit 1
if printf '%s' "$conf" | grep -q 'firewall='; then
  neuf="$(printf '%s' "$conf" | sed 's/firewall=0/firewall=1/')"
else
  neuf="$conf,firewall=1"
fi
[ -f "$WB_DIR/E39.net0" ] || printf '%s\n' "$conf" > "$WB_DIR/E39.net0"
sauver "/etc/pve/firewall/$VMID.fw"
cat > "/etc/pve/firewall/$VMID.fw" <<FW
[OPTIONS]

enable: 1
policy_in: DROP

[RULES]

IN ACCEPT -p udp -dport 53
IN ACCEPT -p tcp -dport 53
FW
qm set "$VMID" --net0 "$neuf" >/dev/null || exit 1
journal "pare-feu de VM activé sur $VMID (net0 firewall=1, policy_in DROP, seul 53 autorisé)"
EOF
  if ((rc == 3)); then
    # Pare-feu du datacenter inactif : la variante serait sans effet, on bascule sur la 1.
    WB_VAR=1
    panne_E39_v1
    return
  fi
  return "$rc"
}

panne_E39_v3() {
  wb_exec_invite "$WB_VMID_DNS01" <<'EOF'
ifc="$(ip -o -4 addr show | awk '$4 ~ /^10\.10\.20\.10\// {print $2; exit}')"
[ -n "$ifc" ] || exit 1
printf '%s\n' "$ifc" > "$WB_DIR/E39.ifc"
ip addr del 10.10.20.10/24 dev "$ifc"
ip addr add 10.10.20.10/29 dev "$ifc"
journal "adresse de $ifc passée de 10.10.20.10/24 à 10.10.20.10/29 (à chaud)"
EOF
}

annuler_E39() {
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_DNS01" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/E39.net0" ]; then
  qm set "$VMID" --net0 "$(cat "$WB_DIR/E39.net0")" >/dev/null && rm -f "$WB_DIR/E39.net0"
fi
restaurer_fichiers
journal "annulation : net0 et pare-feu de la VM $VMID rétablis"
EOF
  # Variantes 1 et 2 : rien à faire dans la VM.
  if [[ "${WB_VAR:-}" == 1 || "${WB_VAR:-}" == 2 ]]; then return 0; fi
  wb_exec_invite "$WB_VMID_DNS01" <<'EOF' || wb_avert "annulation via l'agent QEMU de dns01 impossible (agent absent ?)"
if [ -f "$WB_DIR/E39.ifc" ]; then
  ifc="$(cat "$WB_DIR/E39.ifc")"
  ip addr del 10.10.20.10/29 dev "$ifc" 2>/dev/null || true
  ip addr replace 10.10.20.10/24 dev "$ifc"
  ip route replace default via 10.10.20.1 dev "$ifc"
  rm -f "$WB_DIR/E39.ifc"
  journal "annulation : 10.10.20.10/24 et route par défaut rétablies sur $ifc"
fi
exit 0
EOF
}

resume_E39() {
  echo "Depuis adm01, impossible d'ouvrir une session SSH sur dns01 (délai dépassé)."
}

symptome_E39() {
  wb_symptome "Ticket INC-2605 — De : Karim Benali" \
    "Depuis adm01, je n'arrive plus à me connecter à dns01 :" \
    "« ssh dns01 » part en délai dépassé et le ping ne répond pas non plus." \
    "La VM est pourtant démarrée dans l'interface Proxmox. Personne n'admet y avoir touché." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 00 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E39 3 "$@"; }
fi
