# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E45.sh — M00-E45 « Panne : horloges désynchronisées »
#
# Dans les trois variantes, l'horloge de dns01 est avancée de 10 minutes (date -s). Ce qui
# l'empêche de revenir à l'heure change :
#   1. chrony arrêté et désactivé sur dns01 ;
#   2. NTP (UDP/123) bloqué en entrée sur gw01 ;
#   3. gw01 ne sert plus le temps : directives « allow » retirées de la configuration chrony.
# pve01 n'est jamais décalé. Sauvegardes : /var/lib/workbook/E45.* sur dns01 / gw01.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

_E45_decaler_dns01() {
  wb_exec dns01 >/dev/null <<'EOF'
date -s '+10 minutes' >/dev/null || exit 1
: > "$WB_DIR/E45.decalage"
journal "horloge système avancée de 10 minutes (date -s)"
EOF
}

panne_E45_v1() {
  wb_exec dns01 >/dev/null <<'EOF' || return 1
if systemctl is-enabled -q chrony 2>/dev/null; then echo enabled > "$WB_DIR/E45.chrony"; else echo disabled > "$WB_DIR/E45.chrony"; fi
systemctl disable --now chrony >/dev/null 2>&1 || exit 1
journal "chrony arrêté et désactivé"
EOF
  _E45_decaler_dns01
}

panne_E45_v2() {
  wb_exec gw01 >/dev/null <<'EOF' || return 1
nft_inserer inet filter input 'udp dport 123 counter drop' || exit 1
journal "drop UDP/123 inséré en tête de inet filter input"
EOF
  _E45_decaler_dns01
}

panne_E45_v3() {
  wb_exec gw01 >/dev/null <<'EOF' || return 1
fichiers="$(grep -lE '^[[:space:]]*allow' /etc/chrony/chrony.conf /etc/chrony/conf.d/*.conf 2>/dev/null || true)"
[ -n "$fichiers" ] || exit 1
for f in $fichiers; do
  sauver "$f"
  sed -i -E '/^[[:space:]]*allow/d' "$f"
done
systemctl restart chrony
journal "directives allow retirées de : $fichiers ; chrony redémarré"
EOF
  _E45_decaler_dns01
}

annuler_E45() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
nft_annuler
if [ -f "$WB_DIR/E45.manifeste" ]; then
  restaurer_fichiers
  systemctl restart chrony
fi
journal "annulation : service de temps de gw01 rétabli"
EOF
  wb_exec dns01 MAINTENANT="$(date +%s)" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
if [ -f "$WB_DIR/E45.chrony" ]; then
  if [ "$(cat "$WB_DIR/E45.chrony")" = enabled ]; then systemctl enable chrony >/dev/null 2>&1; fi
  rm -f "$WB_DIR/E45.chrony"
fi
if [ -f "$WB_DIR/E45.decalage" ]; then
  date -s "@$MAINTENANT" >/dev/null
  rm -f "$WB_DIR/E45.decalage"
fi
systemctl restart chrony
journal "annulation : horloge recalée sur adm01, chrony redémarré"
EOF
}

resume_E45() {
  echo "Les horodatages des journaux de dns01 sont en avance d'une dizaine de minutes sur ceux des autres machines."
}

symptome_E45() {
  wb_symptome "Ticket INC-2615 — De : Nadia Roussel" \
    "En préparant le post-mortem d'hier, impossible de corréler les journaux :" \
    "les entrées de dns01 (journalctl, requêtes dnsmasq) sont en avance d'une dizaine de minutes" \
    "sur celles de gw01 et adm01. Pour un hébergeur HDS, la traçabilité horodatée n'est pas" \
    "négociable : remets les horloges d'équerre et explique-moi pourquoi elles ont dérivé." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 00 45"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E45 3 "$@"; }
fi
