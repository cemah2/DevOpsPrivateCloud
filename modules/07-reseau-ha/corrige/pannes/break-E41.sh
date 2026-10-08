# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M07-E41 « Panne : ça part mais ça ne revient pas »
#
# Cible : maquette. Flux visé : srv01 (boucle 10.10.255.21) ↔ srv02 (boucle 10.10.255.22) à travers
# la fabric. Chaque variante crée un chemin de RETOUR qui contourne la fabric par le réseau
# d'administration (vsandbox), et active le filtrage strict par chemin inverse (rp_filter = 1, fichier
# /etc/sysctl.d/99-durcissement-reseau.conf) là où le retour arrive :
#   1. srv02 : route statique 10.10.255.21/32 via l'adresse d'administration de srv01 (posée à chaud)
#      + rp_filter strict sur srv01 ;
#   2. srv02 : règle de routage par politique « from 10.10.255.22 to 10.10.255.21 lookup 199 » et
#      table 199 vers l'adresse d'administration de srv01 (invisible dans « ip route ») + rp_filter
#      strict sur srv01 ;
#   3. leaf02 : route statique FRR « ip route 10.10.255.21/32 10.10.99.251 » (leaf01 par le VLAN 99)
#      dans /etc/frr/frr.conf + rp_filter strict sur leaf01.
# Constat : « ping -I 10.10.255.21 10.10.255.22 » depuis srv01 n'obtient plus de réponse.
# Sauvegardes : /var/lib/workbook/M07-E41.* sur les hôtes modifiés.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

_e41_ping() {
  m07_exec srv01 >/dev/null 2>&1 <<'EOF'
ping -n -c 2 -W 2 -I 10.10.255.21 10.10.255.22 >/dev/null 2>&1
EOF
}
_e41_coupe() { ! _e41_ping; }

_e41_precondition() {
  m07_exec srv01 >/dev/null 2>&1 <<'EOF' || { wb_avert "srv01 : la route vers 10.10.255.22 ne passe pas par la fabric (lab/bin/check 07 41)"; return 1; }
d="$(dev_vers 10.10.255.22 10.10.255.21)"
[ -n "$d" ] && [ "$d" != "$(if_admin)" ]
EOF
  if ! m07_attendre 6 _e41_ping; then
    wb_avert "srv01 ne joint déjà pas srv02 de boucle à boucle : lab/bin/check 07 41 doit être vert avant l'injection"
    return 1
  fi
}

# _e41_rp_strict HÔTE — rp_filter strict, persistant (fichier sysctl) et immédiat.
_e41_rp_strict() {
  m07_exec "$1" >/dev/null <<'EOF'
f=/etc/sysctl.d/99-durcissement-reseau.conf
sysctl_poser "$f" net.ipv4.conf.all.rp_filter 1 || exit 1
sysctl_poser "$f" net.ipv4.conf.default.rp_filter 1 || exit 1
noter_injecte "$f"
journal "rp_filter strict (all, default) dans $f"
EOF
}

_mE41_une() {
  local n="$1" rc=0 ip1
  case "$n" in
    1 | 2)
      ip1="$(m07_exec srv01 2>/dev/null <<'EOF'
ip_admin
EOF
)" || true
      [[ "$ip1" =~ ^10\.10\.99\.[0-9]+$ ]] || { wb_avert "srv01 : adresse d'administration introuvable"; return 1; }
      m07_exec srv02 N="$n" IP1="$ip1" >/dev/null <<'EOF' || rc=$?
i="$(if_admin)"
[ -n "$i" ] || exit 1
if [ "$N" = 1 ]; then
  ip route add 10.10.255.21/32 via "$IP1" dev "$i" || exit 1
  defaire_noter "ip route show 10.10.255.21/32 | grep -q 'via $IP1'" "ip route del 10.10.255.21/32 via $IP1 dev $i"
  journal "route 10.10.255.21/32 via $IP1 dev $i"
else
  ip route add 10.10.255.21/32 via "$IP1" dev "$i" table 199 || exit 1
  ip rule add from 10.10.255.22 to 10.10.255.21 lookup 199 priority 1999 || exit 1
  defaire_noter "ip route show table 199 | grep -q 'via $IP1'" "ip route flush table 199"
  defaire_noter "ip rule show | grep -q '^1999:'" "ip rule del priority 1999"
  journal "règle 1999 from 10.10.255.22 to 10.10.255.21 lookup 199 ; table 199 via $IP1"
fi
EOF
      ((rc == 0)) && { _e41_rp_strict srv01 || rc=1; }
      ;;
    3)
      m07_exec leaf02 >/dev/null <<'EOF' || rc=$?
f=/etc/frr/frr.conf
[ -f "$f" ] && systemctl is-active -q frr || exit 10
subst "$f" '^(router bgp .*)$' 'ip route 10.10.255.21/32 10.10.99.251\n!\n\1' || exit $?
frr_recharger || exit 1
journal "$f : ip route 10.10.255.21/32 10.10.99.251"
EOF
      ((rc == 0)) && { _e41_rp_strict leaf01 || rc=1; }
      ;;
  esac
  if ((rc != 0)); then
    _e41_defaire
    return "$rc"
  fi
  if ! m07_attendre 20 _e41_coupe; then
    m07_journal E41 "variante $n posée mais le ping de boucle à boucle passe encore"
    _e41_defaire
    return 10
  fi
}

_e41_defaire() {
  m07_annuler_hote srv02
  m07_annuler_hote srv01
  m07_annuler_hote leaf02 frr
  m07_annuler_hote leaf01
}

_e41_injecter() {
  _e41_precondition || return 1
  m07_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

verifier_E41() { _e41_coupe; }

annuler_E41() { _e41_defaire; }

resume_E41() {
  echo "srv01 ne joint plus srv02 de boucle à boucle : les requêtes partent, aucune réponse ne revient."
}

symptome_E41() {
  wb_symptome "Ticket INC-3407 — De : Karim Benali" \
    "La sonde de boucle à boucle de la maquette est rouge : depuis srv01," \
    "« ping -I 10.10.255.21 10.10.255.22 » n'obtient aucune réponse. J'ai lancé un tcpdump sur" \
    "srv02 : les requêtes arrivent bien et srv02 répond. Ça part, mais ça ne revient pas." \
    "Lucas a fait des « essais de contournement » pendant la panne de E38, et InfoGér a appliqué" \
    "un guide de durcissement réseau." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 07 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E41 3 "$@"; }
fi
