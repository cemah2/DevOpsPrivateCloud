# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M00-E38 « Panne : plus d'accès Internet depuis INFRA »
#
# Variantes (toutes sur gw01) :
#   1. routage IPv4 désactivé à chaud (sysctl -w), fichier /etc/sysctl.d intact ;
#   2. règle masquerade modifiée : interface de sortie ens19 (trunk) au lieu de ens18 ;
#   3. règle de forward « temporaire » oubliée qui bloque VLAN 20 → WAN.
# Sauvegardes : /var/lib/workbook/E38.* sur gw01. Annulation : --annuler.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

panne_E38_v1() {
  wb_exec gw01 >/dev/null <<'EOF'
sysctl -qw net.ipv4.ip_forward=0
journal "net.ipv4.ip_forward passé à 0 à chaud (sysctl -w) ; configuration persistante inchangée"
EOF
}

panne_E38_v2() {
  wb_exec gw01 >/dev/null <<'EOF'
# La règle de NAT vers le WAN (il peut y en avoir d'autres, ex. vers wg0 depuis E21).
h="$(nft -a list chain ip nat postrouting | awk '/masquerade/ && /"ens18"/ && /# handle/ {print $NF; exit}')"
[ -n "$h" ] || h="$(nft -a list chain ip nat postrouting | awk '/masquerade/ && !/wg[0-9]/ && /# handle/ {print $NF; exit}')"
[ -n "$h" ] || { echo "aucune règle masquerade dans ip nat postrouting" >&2; exit 1; }
ligne="$(nft -a list chain ip nat postrouting | grep -E "# handle $h\$" | sed -E 's/^[[:space:]]+//; s/ # handle [0-9]+$//')"
neuve="$(printf '%s' "$ligne" | sed 's/ens18/ens19/g')"
if [ "$neuve" = "$ligne" ]; then neuve="oifname \"ens19\" $ligne"; fi
nft_remplacer ip nat postrouting "$h" "$neuve" || exit 1
journal "règle masquerade (handle $h) : « $ligne » remplacée par « $neuve »"
EOF
}

panne_E38_v3() {
  wb_exec gw01 >/dev/null <<'EOF'
nft_inserer inet filter forward 'iifname "ens19.20" oifname "ens18" counter drop comment "CHG-0907 isolement temporaire INFRA"' || exit 1
journal "règle de drop VLAN 20 → WAN insérée en tête de inet filter forward"
EOF
}

annuler_E38() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
sysctl -qw net.ipv4.ip_forward=1
nft_annuler
journal "annulation : ip_forward=1, règles nftables rétablies"
EOF
}

resume_E38() {
  echo "Julien signale que dns01 n'arrive plus à faire ses mises à jour : « apt update » échoue sur deb.debian.org."
}

symptome_E38() {
  wb_symptome "Ticket INC-2604 — De : Julien Petit" \
    "Salut, depuis ce matin dns01 ne sort plus du tout vers Internet :" \
    "« apt update » reste bloqué puis échoue sur deb.debian.org, et un curl vers" \
    "https://deb.debian.org n'aboutit pas. Je n'ai rien changé sur la VM." \
    "Tu peux regarder ? Je dois passer les mises à jour de sécurité aujourd'hui." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 00 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E38 3 "$@"; }
fi
