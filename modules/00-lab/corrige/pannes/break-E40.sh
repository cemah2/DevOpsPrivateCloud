# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M00-E40 « Panne : la résolution DNS ne fonctionne plus »
#
# Variantes :
#   1. dnsmasq arrêté sur dns01 + fichier de « tuning » invalide qui l'empêche de redémarrer ;
#   2. serveurs amont de dnsmasq remplacés par une IP morte (192.0.2.53) : zone locale OK,
#      récursion externe KO ;
#   3. résolveur de adm01 pointé vers une IP morte (10.10.20.250) — fichier ou systemd-resolved ;
#   4. UDP/53 bloqué sur gw01 entre VLAN 10 et VLAN 20 (TCP/53 passe encore).
# Sauvegardes : /var/lib/workbook/E40.* sur l'hôte modifié.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

panne_E40_v1() {
  wb_exec dns01 >/dev/null <<'EOF'
f=/etc/dnsmasq.d/90-perf.conf
sauver "$f"
cat > "$f" <<CONF
# PLAT-0731 : agrandir le cache pour absorber la charge des futurs nœuds k8s
cache-size=dix-mille
CONF
systemctl stop dnsmasq
journal "dnsmasq arrêté ; $f ajouté avec une valeur invalide (cache-size)"
EOF
}

panne_E40_v2() {
  wb_exec dns01 >/dev/null <<'EOF'
fichiers="$(grep -lE '^[[:space:]]*server=[0-9]' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf 2>/dev/null || true)"
if [ -n "$fichiers" ]; then
  for f in $fichiers; do
    sauver "$f"
    # Toute la ligne est remplacée : port (#53), interface (@ens18) ou commentaire
    # en fin de ligne ne doivent pas empêcher l'injection.
    sed -i -E 's/^([[:space:]]*server=)[0-9].*$/\1192.0.2.53/' "$f"
  done
  # Garde-fou : l'injection doit avoir réellement eu lieu (sinon : annulation).
  grep -qsE '^[[:space:]]*server=192\.0\.2\.53$' $fichiers || exit 1
else
  # Amont lu dans /etc/resolv.conf de dns01 : on force un amont mort.
  f=/etc/dnsmasq.d/medisphere.conf
  sauver "$f"
  printf '\n# Amont imposé par le prestataire\nno-resolv\nserver=192.0.2.53\n' >> "$f"
fi
systemctl restart dnsmasq
journal "serveurs amont de dnsmasq remplacés par 192.0.2.53"
EOF
}

panne_E40_v3() {
  wb_exec adm01 >/dev/null <<'EOF'
if [ -L /etc/resolv.conf ] && systemctl is-active -q systemd-resolved; then
  ifc="$(ip -o -4 route show default | awk '{print $5; exit}')"
  [ -n "$ifc" ] || exit 1
  printf '%s\n' "$ifc" > "$WB_DIR/E40.resolved"
  resolvectl dns "$ifc" 10.10.20.250
  resolvectl flush-caches 2>/dev/null || true
  journal "systemd-resolved : DNS du lien $ifc forcé à 10.10.20.250"
else
  sauver /etc/resolv.conf
  rm -f /etc/resolv.conf
  printf 'search par1.medisphere.internal\nnameserver 10.10.20.250\n' > /etc/resolv.conf
  journal "/etc/resolv.conf réécrit vers 10.10.20.250"
fi
EOF
}

panne_E40_v4() {
  wb_exec gw01 >/dev/null <<'EOF'
nft_inserer inet filter forward 'iifname "ens19.10" oifname "ens19.20" udp dport 53 counter drop' || exit 1
journal "drop UDP/53 VLAN 10 → VLAN 20 inséré en tête de inet filter forward"
EOF
}

annuler_E40() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
nft_annuler
journal "annulation : règles nftables retirées"
EOF
  wb_exec adm01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
if [ -f "$WB_DIR/E40.resolved" ]; then
  ifc="$(cat "$WB_DIR/E40.resolved")"
  resolvectl revert "$ifc" 2>/dev/null || true
  if systemctl is-active -q systemd-networkd; then
    networkctl reconfigure "$ifc" 2>/dev/null || systemctl restart systemd-networkd
  else
    systemctl restart systemd-resolved
  fi
  rm -f "$WB_DIR/E40.resolved"
fi
restaurer_fichiers
journal "annulation : résolveur de adm01 rétabli"
EOF
  wb_exec dns01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
restaurer_fichiers
systemctl restart dnsmasq
journal "annulation : configuration dnsmasq rétablie et service redémarré"
EOF
}

resume_E40() {
  echo "Sur adm01, « apt update » échoue avec « Temporary failure resolving 'deb.debian.org' »."
}

symptome_E40() {
  wb_symptome "Ticket INC-2607 — De : Nadia Roussel" \
    "Plusieurs remontées ce matin : depuis adm01, « apt update » échoue avec" \
    "« Temporary failure resolving 'deb.debian.org' ». Un « git clone » depuis GitHub échoue" \
    "aussi (« Could not resolve host »). Les accès par adresse IP fonctionnent." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 00 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E40 4 "$@"; }
fi
