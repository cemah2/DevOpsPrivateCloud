# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M07-E36 « Panne : Lyon ne joint plus Paris »
#
# Cible : lyo-gw01 (VMID 2077, routeur du site simulé LYO1). La bordure n'est JAMAIS modifiée.
# Variantes :
#   1. /etc/wireguard/wg2.conf : la clé publique du pair (bordure PAR1) est remplacée par une autre
#      clé valide → plus de poignée de main ;
#   2. /etc/wireguard/wg2.conf : AllowedIPs réduit au réseau du tunnel (10.255.2.0/24) → tunnel et
#      session BGP vivants, mais tout paquet vers PAR1 est refusé par le routage cryptographique ;
#   3. /etc/frr/frr.conf : la route-map d'ENTRÉE de la session avec la bordure est remplacée par celle
#      de SORTIE (copier-coller) → session établie, aucune route de PAR1 acceptée ;
#   4. /etc/sysctl.d/99-cis-durcissement.conf : net.ipv4.ip_forward = 0 (« durcissement CIS ») →
#      lyo-gw01 joint Paris, les postes de Lyon non.
# Constat : lyo-pc01 (VMID 2078) ne joint plus 10.10.20.1 (passerelle du VLAN 20, PAR1).
# Sauvegardes : /var/lib/workbook/M07-E36.* sur lyo-gw01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

_E36_CIBLE=10.10.20.1

_e36_lyon_joint() {
  m07_exec lyo-pc01 C="$_E36_CIBLE" >/dev/null 2>&1 <<'EOF'
ping -n -c 2 -W 2 "$C" >/dev/null 2>&1
EOF
}
_e36_lyon_coupe() { ! _e36_lyon_joint; }

_e36_precondition() {
  m07_exec lyo-gw01 >/dev/null 2>&1 <<'EOF' || { wb_avert "lyo-gw01 : /etc/wireguard/wg2.conf absent ou wg2 non monté (lab/bin/check 07 36)"; return 1; }
[ -f /etc/wireguard/wg2.conf ] && ip link show wg2 >/dev/null 2>&1 && command -v wg-quick >/dev/null
EOF
  if ! m07_attendre 9 _e36_lyon_joint; then
    wb_avert "lyo-pc01 ne joint déjà pas $_E36_CIBLE : lab/bin/check 07 36 doit être vert avant l'injection"
    return 1
  fi
}

_mE36_une() {
  local n="$1" rc=0
  m07_exec lyo-gw01 N="$n" >/dev/null <<'EOF' || rc=$?
w=/etc/wireguard/wg2.conf
f=/etc/frr/frr.conf
synchro() { wg syncconf wg2 <(wg-quick strip wg2); }
case "$N" in
  1)
    k="$(wg genkey | wg pubkey)" || exit 1
    subst "$w" '^(PublicKey[ \t]*=[ \t]*)\S+' "\\g<1>$k" || exit $?
    synchro || exit 1
    journal "$w : clé publique du pair remplacée"
    ;;
  2)
    subst "$w" '^(AllowedIPs[ \t]*=[ \t]*).*$' '\g<1>10.255.2.0/24' || exit $?
    synchro || exit 1
    journal "$w : AllowedIPs = 10.255.2.0/24"
    ;;
  3)
    [ -f "$f" ] && systemctl is-active -q frr || exit 10
    noms="$(sed -nE 's/^[ \t]*neighbor[ \t]+([^ \t]+)[ \t]+remote-as[ \t]+65000[ \t]*$/\1/p' "$f")"
    fait=0
    for nm in $noms; do
      rin="$(sed -nE "s/^[ \\t]*neighbor[ \\t]+$nm[ \\t]+route-map[ \\t]+([^ \\t]+)[ \\t]+in[ \\t]*\$/\\1/p" "$f" | head -n 1)"
      rout="$(sed -nE "s/^[ \\t]*neighbor[ \\t]+$nm[ \\t]+route-map[ \\t]+([^ \\t]+)[ \\t]+out[ \\t]*\$/\\1/p" "$f" | head -n 1)"
      [ -n "$rin" ] && [ -n "$rout" ] && [ "$rin" != "$rout" ] || continue
      e="$(printf '%s' "$nm" | sed 's/[.]/\\./g')"
      subst "$f" "^([ \\t]*neighbor[ \\t]+$e[ \\t]+route-map[ \\t]+)$rin([ \\t]+in)[ \\t]*\$" "\\g<1>$rout\\2" && fait=1
    done
    [ "$fait" = 1 ] || exit 10
    frr_recharger || exit 1
    sleep 2
    vtysh -c 'clear bgp * soft in' >/dev/null 2>&1 || true
    journal "$f : route-map d'entrée de la session bordure remplacée par celle de sortie"
    ;;
  4)
    [ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] || exit 10
    sysctl_poser /etc/sysctl.d/99-cis-durcissement.conf net.ipv4.ip_forward 0 || exit 1
    noter_injecte /etc/sysctl.d/99-cis-durcissement.conf
    journal "sysctl : net.ipv4.ip_forward = 0 (fichier 99-cis-durcissement.conf)"
    ;;
esac
exit 0
EOF
  if ((rc != 0)); then
    _e36_defaire
    return "$rc"
  fi
  if ! m07_attendre 30 _e36_lyon_coupe; then
    m07_journal E36 "variante $n posée mais lyo-pc01 joint toujours PAR1"
    _e36_defaire
    return 10
  fi
}

_e36_defaire() {
  m07_exec lyo-gw01 >/dev/null 2>&1 <<'EOF' || wb_avert "annulation incomplète sur lyo-gw01 (voir /var/lib/workbook/pannes.log)"
tout_defaire
if ip link show wg2 >/dev/null 2>&1; then wg syncconf wg2 <(wg-quick strip wg2) || true; fi
if systemctl is-active -q frr; then frr_recharger || true; sleep 2; vtysh -c 'clear bgp * soft in' >/dev/null 2>&1 || true; fi
exit 0
EOF
}

_e36_injecter() {
  _e36_precondition || return 1
  m07_essayer E36 4 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }
panne_E36_v4() { _e36_injecter 4; }

verifier_E36() { _e36_lyon_coupe; }

annuler_E36() { _e36_defaire; }

resume_E36() {
  echo "L'agence de Lyon (lyo-pc01, 10.30.10.10) ne joint plus aucun service de Paris."
}

symptome_E36() {
  wb_symptome "Ticket INC-3402 — De : Nadia Roussel" \
    "L'agence de Lyon appelle : plus aucun accès aux services de Paris depuis les postes" \
    "(lyo-pc01, 10.30.10.10, en est un). Leur accès Internet fonctionne. InfoGér, qui gère encore" \
    "le routeur de l'agence (lyo-gw01), a « appliqué les correctifs du mois » hier soir." \
    "Côté Paris, personne n'a touché à la bordure." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 07 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E36 4 "$@"; }
fi
