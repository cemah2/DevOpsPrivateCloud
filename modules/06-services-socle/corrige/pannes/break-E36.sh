# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M06-E36 « Panne : les VMs sandbox n'obtiennent plus d'adresse »
#
# Variantes :
#   1. gw01 : l'adresse locale du relais DHCP (dnsmasq, ligne dhcp-relay=10.10.99.1,…) devient
#      10.10.99.11 (« faute de frappe ») → le relais n'écoute plus pour le VLAN 99 ;
#   2. gw01 : règle nftables insérée À CHAUD en tête de la chaîne input (via nft_inserer, hors du rôle
#      pare_feu) qui jette les réponses des serveurs DHCP (UDP 67 depuis 10.10.20.0/24) ;
#   3. Kea (dns01, et dns02 s'il porte Kea) : interfaces-config pointe vers ens19, qui n'existe pas ;
#   4. Kea (dns01, et dns02 s'il porte Kea) : fichier de baux déplacé dans /tmp (« tutoriel ») →
#      Kea 3.0 refuse les chemins hors de /var/lib/kea et ne démarre plus.
# Dans tous les cas, une VM jetable 2069 « m06-sonde-dhcp » (clone lié de l'image dorée current,
# VNet vsandbox, étiquette env-m06) est créée APRÈS l'injection pour constater l'absence de bail ;
# elle reste à disposition de l'apprenant et est détruite par --annuler.
# Sauvegardes : /var/lib/workbook/M06-E36.* sur gw01, dns01, dns02 (texte d'origine, handle nftables).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

# _e36_serveurs_kea — hôtes qui font tourner kea-dhcp4 (dns01, et dns02 après M06-E25).
_e36_serveurs_kea() {
  local h
  for h in dns01 dns02; do
    m06_wb_exec "$h" >/dev/null 2>&1 <<'EOF' && echo "$h"
s="$(service_kea4)" && systemctl is-active -q "$s" && [ -f /etc/kea/kea-dhcp4.conf ]
EOF
  done
}

_e36_precondition() {
  if [[ -z "$(_e36_serveurs_kea)" ]]; then
    wb_avert "kea-dhcp4 n'est pas actif sur dns01 avant la panne : lab/bin/check 06 36"
    return 1
  fi
  m06_wb_exec gw01 >/dev/null <<'EOF' || { wb_avert "gw01 : relais DHCP (dnsmasq, dhcp-relay=10.10.99.1,…) introuvable ou arrêté"; return 1; }
systemctl is-active -q dnsmasq && grep -Ehqs '^[[:space:]]*dhcp-relay=10\.10\.99\.1,' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf
EOF
}

# _e36_sonde — (re)crée la VM 2069 et affiche l'adresse IPv4 qu'elle obtient sur vsandbox (vide si
# aucune après 60 s de fonctionnement). Code 2 si elle ne démarre pas, 3 si le VMID est pris.
_e36_sonde() {
  wb_exec "$WB_PVE_HOST" ID="$_M06_VMID_SONDE" <<'EOF'
if qm status "$ID" >/dev/null 2>&1; then
  qm config "$ID" | grep -q '^name: m06-sonde-dhcp$' || exit 3
  qm stop "$ID" --skiplock 1 >/dev/null 2>&1 || true
  qm destroy "$ID" --purge 1 >/dev/null 2>&1 || exit 2
fi
tpl=""
for v in $(qm list | awk 'NR > 1 && $1 >= 9010 && $1 <= 9029 { print $1 }'); do
  c="$(qm config "$v")"
  if echo "$c" | grep -q '^template: 1' && echo "$c" | grep -Eq '^tags:.*current' && echo "$c" | grep -Eq '^tags:.*debian13'; then
    tpl="$v"; break
  fi
done
[ -n "$tpl" ] || exit 2
qm clone "$tpl" "$ID" --name m06-sonde-dhcp --pool lab >/dev/null 2>&1 || exit 2
qm set "$ID" --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --tags env-m06 --onboot 0 \
  --description "Sonde DHCP de M06-E36 (lab/bin/break 06 36). Détruite par --annuler." >/dev/null || exit 2
qm start "$ID" >/dev/null || exit 2
journal "VM $ID m06-sonde-dhcp créée depuis $tpl"
i=0
until qm guest cmd "$ID" ping >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 60 ] || exit 2; sleep 3
done
sleep 60
qm guest cmd "$ID" network-get-interfaces 2>/dev/null \
  | grep -oE '"ip-address" *: *"10\.10\.99\.[0-9]+"' | grep -oE '10\.10\.99\.[0-9]+' | head -n 1
exit 0
EOF
}

_e36_detruire_sonde() {
  wb_exec "$WB_PVE_HOST" ID="$_M06_VMID_SONDE" >/dev/null <<'EOF' || wb_avert "VM $_M06_VMID_SONDE non détruite (à faire à la main)"
qm status "$ID" >/dev/null 2>&1 || exit 0
qm config "$ID" | grep -q '^name: m06-sonde-dhcp$' || exit 0
qm stop "$ID" --skiplock 1 >/dev/null 2>&1 || true
qm destroy "$ID" --purge 1 >/dev/null
journal "VM $ID m06-sonde-dhcp détruite"
EOF
}

_mE36_une() {
  local n="$1" rc=0 h ip
  case "$n" in
    1)
      m06_wb_exec gw01 >/dev/null <<'EOF' || rc=$?
f="$(grep -lE '^[[:space:]]*dhcp-relay=10\.10\.99\.1,' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf 2>/dev/null | head -n 1)"
[ -n "$f" ] || exit 10
while subst "$f" '^([ \t]*dhcp-relay=)10\.10\.99\.1,' '\g<1>10.10.99.11,'; do :; done
systemctl restart dnsmasq
journal "$f : relais DHCP sur 10.10.99.11"
EOF
      ;;
    2)
      m06_wb_exec gw01 >/dev/null <<'EOF' || rc=$?
nft list chain inet filter input >/dev/null 2>&1 || exit 10
nft_inserer inet filter input 'ip saddr 10.10.20.0/24 udp sport 67 counter drop comment "durcissement INC-3342"' || exit 1
journal "nftables : réponses DHCP des serveurs jetées en entrée (règle à chaud)"
EOF
      ;;
    3 | 4)
      local -a serveurs
      mapfile -t serveurs < <(_e36_serveurs_kea)
      ((${#serveurs[@]} > 0)) || return 1
      for h in "${serveurs[@]}"; do
        m06_wb_exec "$h" N="$n" >/dev/null <<'EOF' || rc=$?
f=/etc/kea/kea-dhcp4.conf
if [ "$N" = 3 ]; then
  subst "$f" '("interfaces"[ \t]*:[ \t]*\[)[^\]]*(\])' '\1 "ens19" \2' || exit $?
  journal "$f : interfaces-config sur ens19"
else
  subst "$f" '("name"[ \t]*:[ \t]*")(/var/lib/kea/)?([^"/]+\.csv")' '\1/tmp/\3' || exit $?
  journal "$f : fichier de baux dans /tmp"
fi
systemctl restart "$(service_kea4)" >/dev/null 2>&1 || true
EOF
      done
      ;;
  esac
  ((rc == 0)) || { _e36_defaire "$n"; return "$rc"; }
  ip="$(_e36_sonde)" || rc=$?
  if ((rc != 0)); then
    _e36_defaire "$n"
    if ((rc == 3)); then wb_avert "VMID $_M06_VMID_SONDE occupé par une autre VM"; else wb_avert "la VM sonde $_M06_VMID_SONDE n'a pas démarré"; fi
    return 1
  fi
  if [[ -n "$ip" ]]; then
    m06_journal E36 "variante $n sans effet : la sonde a obtenu $ip"
    _e36_defaire "$n"
    return 10
  fi
}

# _e36_defaire N — retire la variante N (la VM sonde est gérée à part).
_e36_defaire() {
  local h
  case "$1" in
    1)
      m06_wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01 (relais DHCP)"
if [ -n "$(defaire_subst)" ]; then systemctl restart dnsmasq; fi
EOF
      ;;
    2)
      m06_wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01 (nftables)"
# On ne supprime que la règle qui porte encore notre commentaire (un rechargement complet du
# jeu de règles par le rôle pare_feu réattribue les numéros de handle).
h="$(nft -a list chain inet filter input 2>/dev/null | sed -nE 's/.*comment "durcissement INC-3342".*# handle ([0-9]+)$/\1/p' | head -n 1)"
if [ -n "$h" ]; then
  nft delete rule inet filter input handle "$h" && journal "annulation : règle nftables retirée"
else
  journal "annulation : règle nftables déjà absente (réparation ou rechargement)"
fi
rm -f "$WB_DIR/$WB_EX.nft-ajouts"
EOF
      ;;
    3 | 4)
      for h in dns01 dns02; do
        m06_wb_exec "$h" >/dev/null 2>&1 <<'EOF' || true
[ -f "$WB_DIR/$WB_EX.subst" ] || exit 0
if [ -n "$(defaire_subst)" ]; then systemctl restart "$(service_kea4)" || true; fi
EOF
      done
      ;;
  esac
}

_e36_injecter() {
  _e36_precondition || return 1
  m06_essayer E36 4 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }
panne_E36_v4() { _e36_injecter 4; }

# La constatation est faite par la VM sonde dans _mE36_une (pas d'adresse après 60 s) ; ici, on
# contrôle seulement que la sonde existe toujours et n'a pas d'adresse.
verifier_E36() {
  local o
  o="$(remote "$WB_PVE_HOST" "qm guest cmd $_M06_VMID_SONDE network-get-interfaces" 2>/dev/null)" || return 0
  ! grep -qE '"ip-address" *: *"10\.10\.99\.' <<<"$o"
}

annuler_E36() {
  case "${WB_VAR:-}" in
    1 | 2) _e36_defaire "$WB_VAR" ;;
    3 | 4) _e36_defaire 3 ;;
    *) _e36_defaire 1; _e36_defaire 2; _e36_defaire 3 ;;
  esac
  _e36_detruire_sonde
}

resume_E36() {
  echo "Les VMs du VLAN sandbox (99) démarrent sans adresse IPv4 : plus aucun bail DHCP."
}

symptome_E36() {
  wb_symptome "Ticket INC-3342 — De : Julien Petit" \
    "Mes VMs de test sur le VLAN sandbox démarrent sans adresse IPv4 depuis ce matin : seule" \
    "une adresse fe80:: apparaît sur ens18. Les VMs démarrées hier gardent leur adresse." \
    "Pour que tu puisses reproduire, une VM de test m06-sonde-dhcp (VMID 2069, VNet vsandbox)" \
    "vient d'être démarrée : elle n'a pas d'adresse non plus. Redémarre-la pour retester." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 06 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E36 4 "$@"; }
fi
