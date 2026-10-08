# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M07-E38 « Panne : les gros transferts se figent »
#
# Cible : la fabric de la maquette (spine01-02, leaf01-02) et les serveurs srv01-02.
# Partie commune à toutes les variantes : les liens leaf ↔ spine passent à MTU 1400 des deux côtés
# (« préparation d'une encapsulation ») ; c'est un changement LÉGITIME : avec la découverte du MTU
# du chemin (PMTUD), les flux TCP de 1500 octets s'adaptent. Chaque variante casse la PMTUD :
#   1. leaf01 et leaf02 jettent en SORTIE les ICMP « fragmentation nécessaire » qu'ils émettent
#      (table nftables inet durcissement, « limiter les ICMP émis ») ;
#   2. srv01 et srv02 jettent en ENTRÉE tout ICMP autre que l'écho (table inet durcissement) ;
#   3. srv01 et srv02 reçoivent un pare-feu d'hôte en politique « drop » qui accepte « ct state
#      established » mais oublie « related » : les erreurs ICMP liées aux flux sont jetées.
# Un fichier de test de 8 Mio est publié par le Nginx de srv02 (/export-nuit.bin à la racine du site).
# Constat : depuis srv01 (source 10.10.255.21), la page d'accueil de 10.10.255.22 répond, le
# téléchargement de /export-nuit.bin n'aboutit pas.
# Sauvegardes : /var/lib/workbook/M07-E38.* sur chaque hôte modifié (MTU d'origine, tables, fichier).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

_E38_HOTES=(spine01 spine02 leaf01 leaf02 srv01 srv02)

# _e38_essai petit|gros — requête HTTP de srv01 (boucle) vers srv02 (boucle).
_e38_essai() {
  m07_exec srv01 T="$1" >/dev/null 2>&1 <<'EOF'
if [ "$T" = petit ]; then u=http://10.10.255.22/; d=8; else u=http://10.10.255.22/export-nuit.bin; d=20; fi
curl -sf -o /dev/null --max-time "$d" --interface 10.10.255.21 "$u"
EOF
}
_e38_fige() { _e38_essai petit && ! _e38_essai gros; }

_e38_publier_fichier() {
  m07_exec srv02 >/dev/null <<'EOF'
r="$(nginx -T 2>/dev/null | sed -nE 's/^[ \t]*root[ \t]+([^;]+);.*/\1/p' | head -n 1)"
[ -n "$r" ] && [ -d "$r" ] || exit 1
f="$r/export-nuit.bin"
[ -e "$f" ] || { sauver "$f"; head -c 8388608 /dev/urandom >"$f"; chmod 644 "$f"; noter_injecte "$f"; journal "$f publié (8 Mio)"; }
exit 0
EOF
}

_e38_precondition() {
  local h
  for h in "${_E38_HOTES[@]}"; do
    m07_exec "$h" >/dev/null 2>&1 <<'EOF' || { wb_avert "$h : agent QEMU, nftables ou adresse de boucle manquants (lab/bin/check 07 38)"; return 1; }
command -v nft >/dev/null && command -v python3 >/dev/null
EOF
  done
  _e38_publier_fichier || { wb_avert "srv02 : impossible de publier le fichier de test (racine Nginx introuvable)"; return 1; }
  if ! _e38_essai petit || ! m07_attendre 6 _e38_essai gros; then
    wb_avert "le transfert srv01 → srv02 (boucles) échoue déjà : lab/bin/check 07 38 doit être vert avant l'injection"
    return 1
  fi
}

# Partie commune : liens leaf ↔ spine à 1400 des deux côtés.
_e38_mtu_fabric() {
  local h cibles
  for h in leaf01 leaf02 spine01 spine02; do
    case "$h" in
      leaf01) cibles=10.10.255.12/32 ;;
      leaf02) cibles=10.10.255.11/32 ;;
      *) cibles="10.10.255.11/32 10.10.255.12/32" ;;
    esac
    m07_exec "$h" CIBLES="$cibles" >/dev/null <<'EOF' || return 1
n=0
for c in $CIBLES; do
  for i in $(devs_ecmp "$c"); do
    mtu_poser "$i" 1400 && n=$((n + 1))
  done
done
[ "$n" -gt 0 ] || exit 1
journal "MTU 1400 sur les liens de fabric ($n interface(s))"
EOF
  done
}

_mE38_une() {
  local n="$1" h rc=0
  # (re)publication du fichier de test : une variante sans effet a tout défait, fichier compris
  _e38_publier_fichier || rc=1
  if ((rc == 0)); then _e38_mtu_fabric || rc=1; fi
  if ((rc == 0)); then
    case "$n" in
      1) set -- leaf01 leaf02 ;;
      *) set -- srv01 srv02 ;;
    esac
    for h in "$@"; do
      m07_exec "$h" N="$n" >/dev/null <<'EOF' || rc=$?
case "$N" in
  1)
    nft_table_poser durcissement '  chain sortie {
    type filter hook output priority -10; policy accept;
    icmp type destination-unreachable icmp code frag-needed counter drop comment "limiter les ICMP emis"
  }' || exit $?
    ;;
  2)
    nft_table_poser durcissement '  chain entree {
    type filter hook input priority -10; policy accept;
    icmp type { echo-request, echo-reply } accept
    ip protocol icmp counter drop comment "ICMP : echo seulement"
  }' || exit $?
    ;;
  3)
    nft_table_poser filtre_hote '  chain entree {
    type filter hook input priority -10; policy drop;
    iif "lo" accept
    ct state established accept
    meta l4proto ipv6-icmp accept
    ip protocol vrrp accept
    tcp dport { 22, 80, 179 } accept
    udp dport 68 accept
    icmp type echo-request accept
    counter comment "rejete par la politique"
  }' || exit $?
    ;;
esac
journal "variante $N : filtrage ICMP posé"
EOF
    done
  fi
  if ((rc != 0)); then
    _e38_defaire
    return "$rc"
  fi
  if ! m07_attendre 30 _e38_fige; then
    m07_journal E38 "variante $n posée mais le transfert aboutit (ou la page d'accueil ne répond plus)"
    _e38_defaire
    return 10
  fi
}

_e38_defaire() {
  local h
  for h in srv01 srv02 leaf01 leaf02 spine01 spine02; do
    m07_annuler_hote "$h"
  done
}

_e38_injecter() {
  _e38_precondition || { _e38_defaire; return 1; }
  m07_essayer E38 3 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }

verifier_E38() { _e38_fige; }

annuler_E38() { _e38_defaire; }

resume_E38() {
  echo "Les gros transferts entre srv01 et srv02 (à travers la fabric) se figent ; les petites requêtes passent."
}

symptome_E38() {
  wb_symptome "Ticket INC-3404 — De : Julien Petit" \
    "Le transfert de l'export de nuit entre srv01 et srv02 ne finit plus : depuis srv01," \
    "« curl --interface 10.10.255.21 http://10.10.255.22/export-nuit.bin » reste à 0 octet puis" \
    "expire. La page d'accueil de srv02 répond pourtant instantanément, ping aussi, SSH aussi." \
    "InfoGér a « préparé la fabric pour l'encapsulation » hier et « durci » quelques machines." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 07 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E38 3 "$@"; }
fi
