# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M07-E40 « Panne : l'agrégat a perdu un lien »
#
# Cible : net01 (VMID 2070) : bond Linux 802.3ad dans un espace de noms (côté « serveur ») relié par
# des paires veth à un bond Open vSwitch lacp=active (côté « commutateur », pont br-lab) — état de
# M07-E17. Le script découvre lui-même l'espace de noms, le bond et les membres.
# Variantes (le DEUXIÈME membre du bond Linux est visé) :
#   1. l'extrémité « commutateur » de sa paire veth est mise administrativement DOWN (câble coupé
#      côté commutateur : le membre passe en NO-CARRIER) ;
#   2. Open vSwitch : lacp=off sur le port agrégé → plus de LACPDU, le bond Linux ne garde qu'un
#      agrégateur d'un seul port (partenaire inconnu) ;
#   3. le membre est retiré du bond Linux (nomaster) : lien UP, mais hors de l'agrégat.
# Constat : l'agrégateur actif du bond Linux n'a plus qu'un port.
# Sauvegardes : /var/lib/workbook/M07-E40.* sur net01 (actions à défaire, notées avec leur test).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

# Fonctions distantes : trouver le bond 802.3ad et compter les ports de l'agrégateur actif.
read -r -d '' _E40_AIDE <<'EOF' || true
trouver_bond() {
  local ns b
  for ns in "" $(ip netns list 2>/dev/null | awk '{ print $1 }'); do
    for b in $(nsexec "$ns" sh -c 'ls /proc/net/bonding 2>/dev/null'); do
      if nsexec "$ns" grep -q '802.3ad' "/proc/net/bonding/$b" 2>/dev/null; then
        printf '%s %s\n' "${ns:-.}" "$b"
        return 0
      fi
    done
  done
  return 1
}
nb_ports_actifs() {
  nsexec "$1" awk '/^Active Aggregator Info/ { a = 1 } a && /Number of ports:/ { print $NF; exit }' "/proc/net/bonding/$2" 2>/dev/null
}
EOF

_e40_ports() {
  { printf '%s\n' "$_E40_AIDE"; cat <<'EOF'; } | m07_exec net01 2>/dev/null
set -- $(trouver_bond) || exit 1
ns="$1"; [ "$ns" = . ] && ns=""
nb_ports_actifs "$ns" "$2"
EOF
}
_e40_degrade() { local p; p="$(_e40_ports)"; [[ -n "$p" && "$p" -lt 2 ]]; }

_e40_precondition() {
  local p
  p="$(_e40_ports)"
  if [[ -z "$p" || "$p" -lt 2 ]]; then
    wb_avert "net01 : aucun bond 802.3ad à deux ports actifs trouvé (état de M07-E17) : lab/bin/check 07 40"
    return 1
  fi
}

_mE40_une() {
  local n="$1" rc=0 delai=20
  { printf '%s\n' "$_E40_AIDE"; cat <<'EOF'; } | m07_exec net01 N="$n" >/dev/null || rc=$?
set -- $(trouver_bond) || exit 1
ns="$1"; [ "$ns" = . ] && ns=""
b="$2"
s="$(nsexec "$ns" cat "/sys/class/net/$b/bonding/slaves" | awk '{ print $2 }')"
[ -n "$s" ] || exit 1
case "$N" in
  1)
    lien="$(nsexec "$ns" cat "/sys/class/net/$s/iflink")"
    moi="$(nsexec "$ns" cat "/sys/class/net/$s/ifindex")"
    pns=""; pair=""
    for c in "" $(ip netns list | awk '{ print $1 }'); do
      [ "$c" = "$ns" ] && continue
      for d in $(nsexec "$c" ls /sys/class/net); do
        if [ "$(nsexec "$c" cat "/sys/class/net/$d/ifindex" 2>/dev/null)" = "$lien" ] \
          && [ "$(nsexec "$c" cat "/sys/class/net/$d/iflink" 2>/dev/null)" = "$moi" ]; then
          pns="$c"; pair="$d"
        fi
      done
    done
    [ -n "$pair" ] || exit 10
    nsip "$pns" link set dev "$pair" down || exit 1
    defaire_noter "nsip '$pns' -o link show dev '$pair' | grep -qv '[<,]UP[,>]'" "nsip '$pns' link set dev '$pair' up"
    journal "extrémité commutateur $pair (netns '$pns') de $s mise DOWN"
    ;;
  2)
    command -v ovs-vsctl >/dev/null || exit 10
    p="$(ovs-vsctl --bare --columns=name find port lacp=active | head -n 1)"
    [ -n "$p" ] || exit 10
    ovs-vsctl set port "$p" lacp=off || exit 1
    defaire_noter "[ \"\$(ovs-vsctl get port '$p' lacp)\" = off ]" "ovs-vsctl set port '$p' lacp=active"
    journal "Open vSwitch : lacp=off sur $p"
    ;;
  3)
    nsip "$ns" link set dev "$s" nomaster || exit 1
    defaire_noter "! nsip '$ns' -o link show dev '$s' | grep -q ' master '" "nsip '$ns' link set dev '$s' down; nsip '$ns' link set dev '$s' master '$b'; nsip '$ns' link set dev '$s' up"
    journal "$s retiré du bond $b (netns '$ns')"
    ;;
esac
exit 0
EOF
  if ((rc != 0)); then
    _e40_defaire
    return "$rc"
  fi
  # Sans LACPDU, le partenaire n'expire qu'au bout de 3 s (lacp_rate fast) ou 90 s (slow).
  ((n == 2)) && delai=100
  if ! m07_attendre "$delai" _e40_degrade; then
    m07_journal E40 "variante $n posée mais l'agrégateur actif a toujours plusieurs ports"
    _e40_defaire
    return 10
  fi
}

_e40_defaire() { m07_annuler_hote net01; }

_e40_injecter() {
  _e40_precondition || return 1
  m07_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() { _e40_degrade; }

annuler_E40() { _e40_defaire; }

resume_E40() {
  echo "L'agrégat LACP de net01 ne travaille plus que sur un lien (débit divisé par deux, plus de redondance)."
}

symptome_E40() {
  wb_symptome "Ticket INC-3406 — De : Karim Benali" \
    "La sonde de net01 signale que l'agrégat LACP entre l'espace de noms « serveur » et le" \
    "commutateur Open vSwitch ne compte plus qu'un port actif : débit divisé par deux et plus" \
    "aucune redondance. Personne n'admet avoir touché à net01. Remets les deux liens dans" \
    "l'agrégat, et dis-moi ce qu'aurait vu un vrai commutateur." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 07 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E40 3 "$@"; }
fi
