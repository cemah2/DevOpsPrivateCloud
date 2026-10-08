# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M07-E42 « Panne : la fabric perd la moitié de son trafic »
#
# Cible : fabric leaf-spine de la maquette (M07-E14 : BGP unnumbered, ECMP sur les deux spines).
# Variantes :
#   1. spine02 : net.ipv4.ip_forward = 0 (fichier /etc/sysctl.d/99-durcissement.conf) → les sessions
#      BGP restent établies, spine02 annonce toujours les routes… et jette tout ce qu'il devrait
#      relayer : environ la moitié des couples source/destination ne passent plus ;
#   2. leaf01 et leaf02 : « maximum-paths 1 » dans l'address-family IPv4 → plus d'ECMP, tout passe par
#      un seul spine (capacité divisée par deux, plus de partage de charge) ;
#   3. spine02 : entrée « deny 1 » ajoutée en tête de la route-map d'entrée de ses voisins → spine02
#      n'apprend plus rien des leaves, les leaves n'ont plus qu'un chemin.
# Constat : leaf01 n'a plus qu'un saut vers la boucle de leaf02 (10.10.255.12), ou un spine ne relaie
# plus (ip_forward = 0) alors que l'ECMP est toujours en place.
# Sauvegardes : /var/lib/workbook/M07-E42.* sur les hôtes modifiés.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

_e42_sauts() {
  m07_exec leaf01 2>/dev/null <<'EOF'
devs_ecmp 10.10.255.12/32 | wc -l
EOF
}
_e42_spines_relaient() {
  local h
  for h in spine01 spine02; do
    m07_exec "$h" >/dev/null 2>&1 <<'EOF' || return 1
[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]
EOF
  done
}
_e42_casse() {
  local s
  s="$(_e42_sauts)"
  [[ -n "$s" ]] || return 1
  ((s < 2)) || ! _e42_spines_relaient
}

_e42_precondition() {
  local s
  s="$(_e42_sauts)"
  if [[ -z "$s" || "$s" -lt 2 ]] || ! _e42_spines_relaient; then
    wb_avert "la fabric n'est pas en ECMP sur deux spines (leaf01 → 10.10.255.12) : lab/bin/check 07 42"
    return 1
  fi
}

_mE42_une() {
  local n="$1" h rc=0
  case "$n" in
    1)
      m07_exec spine02 >/dev/null <<'EOF' || rc=$?
f=/etc/sysctl.d/99-durcissement.conf
sysctl_poser "$f" net.ipv4.ip_forward 0 || exit 1
noter_injecte "$f"
journal "net.ipv4.ip_forward = 0 dans $f"
EOF
      ;;
    2)
      for h in leaf01 leaf02; do
        m07_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/frr/frr.conf
if grep -Eq '^[[:space:]]*maximum-paths[[:space:]]+[0-9]+' "$f"; then
  subst "$f" '^([ \t]*maximum-paths[ \t]+)(?!1\b)\d+' '\g<1>1' || exit $?
else
  subst "$f" '^([ \t]*)address-family ipv4 unicast[ \t]*$' '\g<0>\n\1 maximum-paths 1' || exit $?
fi
frr_recharger || exit 1
journal "$f : maximum-paths 1"
EOF
      done
      ;;
    3)
      m07_exec spine02 >/dev/null <<'EOF' || rc=$?
f=/etc/frr/frr.conf
k=0
for rm in $(sed -nE 's/^[ \t]*neighbor[ \t]+[^ \t]+[ \t]+route-map[ \t]+([^ \t]+)[ \t]+in[ \t]*$/\1/p' "$f" | sort -u); do
  grep -Eq "^route-map[[:space:]]+$rm[[:space:]]+deny[[:space:]]+1([^0-9]|\$)" "$f" && continue
  subst "$f" "^route-map[ \\t]+$rm[ \\t]+(permit|deny)[ \\t]+\\d+" "route-map $rm deny 1\\n!\\n\\g<0>" && k=$((k + 1))
done
[ "$k" -gt 0 ] || exit 10
frr_recharger || exit 1
sleep 2
vtysh -c 'clear bgp * soft in' >/dev/null 2>&1 || true
journal "$f : « deny 1 » en tête de $k route-map(s) d'entrée"
EOF
      ;;
  esac
  if ((rc != 0)); then
    _e42_defaire
    return "$rc"
  fi
  if ! m07_attendre 30 _e42_casse; then
    m07_journal E42 "variante $n posée mais l'ECMP et le relais sont intacts"
    _e42_defaire
    return 10
  fi
}

_e42_defaire() {
  m07_annuler_hote spine02 frr
  m07_annuler_hote leaf01 frr
  m07_annuler_hote leaf02 frr
  m07_exec spine02 >/dev/null 2>&1 <<'EOF' || true
vtysh -c 'clear bgp * soft in' >/dev/null 2>&1 || true
EOF
}

_e42_injecter() {
  _e42_precondition || return 1
  m07_essayer E42 3 "$1"
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }

verifier_E42() { _e42_casse; }

annuler_E42() { _e42_defaire; }

resume_E42() {
  echo "La fabric de la maquette a perdu la moitié de ses chemins : une partie des flux échoue, ou tout passe par un seul spine."
}

symptome_E42() {
  local detail
  if [[ "${WB_VAR:-}" == 1 ]]; then
    detail="Certains couples de machines ne se joignent plus (srv01 joint leaf02 mais pas srv02, par exemple), d'autres oui, et ça ne bouge pas d'une minute à l'autre. Toutes les sessions BGP sont établies."
  else
    detail="Tout le trafic est-ouest passe par un seul spine : l'autre ne voit plus passer aucun paquet de la fabric et la latence monte sous charge. Toutes les sessions BGP sont établies."
  fi
  wb_symptome "Ticket INC-3408 — De : Karim Benali" \
    "La fabric de la maquette a perdu la moitié d'elle-même." \
    "$detail" \
    "C'est exactement le genre de panne que je veux savoir diagnostiquer avant Kubernetes." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 07 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E42 3 "$@"; }
fi
