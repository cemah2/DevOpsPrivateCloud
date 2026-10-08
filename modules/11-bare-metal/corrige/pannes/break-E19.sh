# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E19.sh — M11-E19 « Panne : le serveur ne démarre pas sur le réseau »
#
# Variantes :
#   1. Kea (dns01 et dns02) : le serveur suivant (« next-server ») du VLAN 60 pointe vers
#      10.10.60.12 au lieu de pxe01 (« correction d'une adresse » mal recopiée) → l'offre arrive,
#      le TFTP part vers une adresse muette (TFTP open timeout / PXE-E32) ;
#   2. Kea (dns01 et dns02) : le test de la classe BIOS compare l'option 93 à 0x0006 (IA32 EFI) au
#      lieu de 0x0000 → les clients BIOS reçoivent une offre SANS fichier de démarrage ; UEFI démarre ;
#   3. pxe01 : les chargeurs iPXE de la racine TFTP passent en 0600 root:root (« copie avec un
#      umask restrictif ») → tftpd-hpa (compte tftp) refuse : « Access violation » / « Permission denied » ;
#   4. passerelles (gw01, gw02) : les lignes « dhcp-relay » du VLAN 60 sont commentées dans la
#      configuration de dnsmasq (« ménage » après la partie MAAS), dnsmasq redémarré → plus aucune
#      offre sur le VLAN 60 ; le VLAN 99 n'est pas touché.
# Sauvegardes : /var/lib/workbook/M11-E19.* sur chaque hôte touché (textes d'origine, empreintes).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m11-commun.sh
source "$WB_ROOT/modules/11-bare-metal/corrige/pannes/_m11-commun.sh"

# Serveurs Kea et passerelles présents sur ce lab
_e19_kea() { local h; for h in dns01 dns02; do if m11_existe "$h"; then echo "$h"; fi; done; }
_e19_gw() { local h; for h in gw01 gw02; do if m11_existe "$h"; then echo "$h"; fi; done; }

# _e19_tftp_ok — les deux chargeurs se lisent en TFTP sur pxe01 (sonde lancée sur pxe01).
_e19_tftp_ok() {
  m11_wb_exec pxe01 IP="$_M11_PXE_IP" >/dev/null 2>&1 <<'EOF'
tftp_lire "$IP" undionly.kpxe && tftp_lire "$IP" ipxe.efi
EOF
}

# _e19_kea_contient HÔTE REGEX — la configuration de Kea de l'hôte contient REGEX et Kea est actif.
_e19_kea_contient() {
  m11_wb_exec "$1" RX="$2" >/dev/null 2>&1 <<'EOF'
s="$(service_kea4)" || exit 1
systemctl is-active -q "$s" && grep -Eq -- "$RX" /etc/kea/kea-dhcp4.conf
EOF
}

# _e19_relais_actif — au moins une passerelle relaie le VLAN 60 (ligne non commentée, dnsmasq actif).
_e19_relais_actif() {
  local h
  for h in $(_e19_gw); do
    if m11_wb_exec "$h" >/dev/null 2>&1 <<'EOF'
systemctl is-active -q dnsmasq && grep -Eqs '^[[:space:]]*dhcp-relay=10\.10\.60\.' /etc/dnsmasq.d/*.conf /etc/dnsmasq.conf
EOF
    then return 0; fi
  done
  return 1
}

_e19_precondition() {
  if ! _e19_tftp_ok; then
    wb_avert "pxe01 ne sert pas déjà les chargeurs en TFTP : lab/bin/check 11 19"
    return 1
  fi
  if ! _e19_kea_contient dns01 '10\.10\.60\.0/24'; then
    wb_avert "Kea (dns01) ne tourne pas ou ne sert pas le sous-réseau 10.10.60.0/24 : lab/bin/check 11 19"
    return 1
  fi
  if ! _e19_relais_actif; then
    wb_avert "aucune passerelle ne relaie le VLAN 60 : lab/bin/check 11 19"
    return 1
  fi
}

_mE19_une() {
  local n="$1" rc=0 h touche=0
  case "$n" in
    1 | 2)
      local rx rempl
      if [[ "$n" == 1 ]]; then
        rx='"next-server"(\s*):(\s*)"10\.10\.60\.10"'
        rempl='"next-server"\1:\2"10.10.60.12"'
      else
        rx='option\[93\]\.hex(\s*)==(\s*)0x0000'
        rempl='option[93].hex\1==\g<2>0x0006'
      fi
      for h in $(_e19_kea); do
        rc=0
        m11_wb_exec "$h" RX="$rx" REMPL="$rempl" >/dev/null <<'EOF' || rc=$?
subst /etc/kea/kea-dhcp4.conf "$RX" "$REMPL" || exit $?
if ! kea_relancer; then
  defaire_subst >/dev/null
  kea_relancer
  exit 1
fi
journal "kea-dhcp4.conf modifié ($RX), Kea redémarré"
EOF
        if ((rc == 0)); then touche=1; elif ((rc != 10)); then _e19_defaire; return 1; fi
      done
      ((touche)) || return 10
      ;;
    3)
      m11_wb_exec pxe01 >/dev/null <<'EOF' || rc=$?
r="$(tftp_racine)"
[ -n "$r" ] && [ -f "$r/undionly.kpxe" ] && [ -f "$r/ipxe.efi" ] || exit 10
for f in "$r/undionly.kpxe" "$r/ipxe.efi"; do
  sauver "$f"
  chown root:root "$f"
  chmod 0600 "$f"
  noter_injecte "$f"
done
journal "chargeurs iPXE de $r passés en 0600 root:root"
EOF
      ((rc == 0)) || return "$rc"
      ;;
    4)
      for h in $(_e19_gw); do
        rc=0
        m11_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
n=0
for f in /etc/dnsmasq.d/*.conf /etc/dnsmasq.conf; do
  [ -f "$f" ] || continue
  while subst "$f" '^([ \t]*)(dhcp-relay=10\.10\.60\.[^\n]*)$' '\1# \2'; do n=$((n + 1)); [ "$n" -lt 8 ] || break; done
done
[ "$n" -gt 0 ] || exit 10
systemctl restart dnsmasq
journal "$n ligne(s) dhcp-relay du VLAN 60 commentée(s), dnsmasq redémarré"
EOF
        if ((rc == 0)); then touche=1; elif ((rc != 10)); then _e19_defaire; return 1; fi
      done
      ((touche)) || return 10
      ;;
  esac
  sleep 2
  verifier_E19_n "$n" || { _e19_defaire; return 10; }
}

verifier_E19_n() {
  case "$1" in
    1) _e19_kea_contient dns01 '"next-server"[[:space:]]*:[[:space:]]*"10\.10\.60\.12"' ;;
    2) _e19_kea_contient dns01 'option\[93\]\.hex[[:space:]]*==[[:space:]]*0x0006' ;;
    3) ! _e19_tftp_ok ;;
    4) ! _e19_relais_actif ;;
    *) return 1 ;;
  esac
}

# _e19_defaire — défait tout ce que la panne a posé, sur chaque hôte (sans écraser une réparation).
_e19_defaire() {
  local h
  for h in $(_e19_kea); do
    m11_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (Kea) : kea-dhcp4 -t /etc/kea/kea-dhcp4.conf"
[ -f "$WB_DIR/$WB_EX.subst" ] || exit 0
if [ -n "$(defaire_subst)" ]; then kea_relancer; fi
EOF
  done
  m11_wb_exec pxe01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pxe01 (chargeurs TFTP)"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
EOF
  for h in $(_e19_gw); do
    m11_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (relais) : systemctl status dnsmasq"
[ -f "$WB_DIR/$WB_EX.subst" ] || exit 0
if [ -n "$(defaire_subst)" ]; then systemctl restart dnsmasq; fi
EOF
  done
}

_e19_injecter() {
  _e19_precondition || return 1
  m11_essayer E19 4 "$1"
}

panne_E19_v1() { _e19_injecter 1; }
panne_E19_v2() { _e19_injecter 2; }
panne_E19_v3() { _e19_injecter 3; }
panne_E19_v4() { _e19_injecter 4; }

verifier_E19() { verifier_E19_n "${WB_VAR:-0}"; }

annuler_E19() { _e19_defaire; }

resume_E19() {
  case "${WB_VAR:-0}" in
    2) echo "Les serveurs BIOS du VLAN 60 ne démarrent plus sur le réseau ; les serveurs UEFI, si." ;;
    4) echo "Plus aucun serveur du VLAN 60 n'obtient d'adresse au démarrage réseau." ;;
    *) echo "Les serveurs du VLAN 60 obtiennent une adresse mais ne chargent pas leur chargeur réseau." ;;
  esac
}

symptome_E19() {
  local -a l
  case "${WB_VAR:-0}" in
    1) l=("bm01 et bm03 ne démarrent plus sur le réseau. Sur la console, la machine obtient bien"
      "une adresse en 10.10.60.1xx, puis reste longtemps sur le téléchargement du chargeur"
      "et finit par abandonner (BIOS : « PXE-E32: TFTP open timeout » ou équivalent ; UEFI :"
      "retour au menu du micrologiciel). Personne n'a touché à pxe01, qui répond au ping.") ;;
    2) l=("bm01 (BIOS) ne démarre plus sur le réseau : il obtient une adresse, puis la console"
      "affiche « No boot filename received » et passe au disque (vide). bm03 (UEFI), lui, démarre"
      "normalement et s'installe. Rien n'a été changé sur pxe01.") ;;
    3) l=("bm01 et bm03 ne démarrent plus sur le réseau. Ils obtiennent une adresse, contactent"
      "bien pxe01, puis la console affiche une erreur au moment du téléchargement du chargeur"
      "(selon la machine : « Access violation », « File not found » ou « TFTP error »)."
      "pxe01 répond pourtant en HTTPS normalement. On a recopié les chargeurs hier soir.") ;;
    *) l=("Plus aucun serveur du VLAN 60 ne démarre sur le réseau : bm01 et bm03 restent"
      "sur « DHCP… » (ou « No DHCP or proxyDHCP offers were received ») puis passent au disque."
      "Les VMs du VLAN 99 obtiennent leur adresse normalement. Il y a eu du ménage hier"
      "après la fin de l'évaluation de MAAS.") ;;
  esac
  wb_symptome "Ticket INC-3841 — De : Nadia Roussel" "${l[@]}" "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 11 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 11 E19 4 "$@"; }
fi
