# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M00-E43 « Panne : le site PAR2 est injoignable »
#
# Variantes (toutes sur gw01, interface wg0) :
#   1. clé publique du pair (hp01) remplacée dans /etc/wireguard/wg0.conf puis « wg syncconf » ;
#   2. AllowedIPs du pair amputé de 10.20.0.0/16 (tunnel établi, mais PAR2 non routé dans wg0) ;
#   3. UDP/51820 bloqué en entrée dans nftables.
# L'endpoint erroné n'est pas proposé : le roaming WireGuard le corrige dès que hp01 émet
# (voir corrigé). Sauvegardes : /var/lib/workbook/E43.* sur gw01.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

panne_E43_v1() {
  wb_exec gw01 >/dev/null <<'EOF'
f=/etc/wireguard/wg0.conf
[ -f "$f" ] || exit 1
ancienne="$(sed -n '/^\[Peer\]/,$ s/^[[:space:]]*PublicKey[[:space:]]*=[[:space:]]*//p' "$f" | head -n 1 | tr -d '[:space:]')"
[ -n "$ancienne" ] || exit 1
nouvelle="$(wg genkey | wg pubkey)"
sauver "$f"
sed -i "s#${ancienne}#${nouvelle}#" "$f"
wg syncconf wg0 <(wg-quick strip wg0) || exit 1
journal "clé publique du pair de wg0 : $ancienne → $nouvelle (fichier + syncconf)"
EOF
}

panne_E43_v2() {
  wb_exec gw01 >/dev/null <<'EOF'
f=/etc/wireguard/wg0.conf
[ -f "$f" ] || exit 1
sauver "$f"
sed -i -E '/^\[Peer\]/,$ {
  /^[[:space:]]*AllowedIPs/ {
    s#,[[:space:]]*10\.20\.0\.0/16##
    s#10\.20\.0\.0/16[[:space:]]*,[[:space:]]*##
  }
}' "$f"
if cmp -s "$f" "$WB_DIR/E43._etc_wireguard_wg0.conf.orig"; then
  # 10.20.0.0/16 n'apparaît pas tel quel : on restreint à chaud au seul /30 d'interconnexion.
  pair="$(wg show wg0 peers | head -n 1)"
  [ -n "$pair" ] || exit 1
  wg set wg0 peer "$pair" allowed-ips 10.255.0.2/32 || exit 1
  journal "AllowedIPs du pair $pair réduit à chaud à 10.255.0.2/32"
else
  wg syncconf wg0 <(wg-quick strip wg0) || exit 1
  journal "10.20.0.0/16 retiré de AllowedIPs dans $f (fichier + syncconf)"
fi
EOF
}

panne_E43_v3() {
  wb_exec gw01 >/dev/null <<'EOF'
nft_inserer inet filter input 'udp dport 51820 counter drop' || exit 1
journal "drop UDP/51820 inséré en tête de inet filter input"
EOF
}

annuler_E43() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
nft_annuler
restaurer_fichiers
if ip link show wg0 >/dev/null 2>&1; then
  wg syncconf wg0 <(wg-quick strip wg0) || true
fi
journal "annulation : wg0.conf restauré, syncconf, règles nftables retirées"
EOF
}

resume_E43() {
  echo "Le stockage pbs-par2 apparaît grisé (point d'interrogation) dans l'interface de pve01."
}

symptome_E43() {
  wb_symptome "Ticket INC-2614 — De : Nadia Roussel" \
    "Alerte de supervision : le stockage pbs-par2 apparaît avec un point d'interrogation gris" \
    "dans l'interface de pve01, et « ssh pbs01 » depuis adm01 ne répond plus." \
    "J'ai vérifié via l'iLO : hp01 est allumé, la console PBS est accessible, aucune erreur." \
    "Le site PAR2 semble coupé du reste du monde." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 00 43"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E43 3 "$@"; }
fi
