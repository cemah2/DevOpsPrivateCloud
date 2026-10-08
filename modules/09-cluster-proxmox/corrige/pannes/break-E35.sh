# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M09-E35 « Panne : le cluster a perdu le quorum »
#
# Préalable commun : si des ressources HA existent, la pile HA est désarmée (disarm-ha freeze) avant
# l'injection, sinon chaque nœud privé de quorum se clôturerait (watchdog) et redémarrerait.
#
# Variantes :
#   1. nftables DANS hv02 et hv03 : table « inet infoger_durcissement » qui jette en entrée l'UDP
#      5404-5412 (ports knet de Corosync : 5405 pour le lien 0, 5406 pour le lien 1) « script de
#      durcissement d'InfoGér » → trois nœuds isolés, aucune partition majoritaire ;
#   2. /etc/pve/corosync.conf : « expected_votes: 7 » ajouté dans la section quorum (config_version
#      incrémentée, propagée par pmxcfs, rechargée par corosync) → quorum = 4 votes, 3 présents ;
#   3. /etc/corosync/authkey de hv02 et de hv03 remplacées chacune par une clé différente (« rotation
#      de clé » interrompue), corosync redémarré → plus aucun nœud ne déchiffre les autres.
# Sauvegardes : /var/lib/workbook/M09-E35.* sur le nœud touché ; état local ~/.local/state/workbook/M09-E35/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_e35_precondition() {
  m09_cluster_sain || return 1
  local n
  for n in hv02 hv03; do
    if m09_ssh "$n" "nft list table inet $_M09_TABLE" >/dev/null 2>&1; then
      wb_avert "$n : une table nftables inet $_M09_TABLE existe déjà (panne précédente non close ?)"
      return 1
    fi
  done
  if m09_ssh hv01 "grep -Eq '^[[:space:]]*expected_votes:' /etc/pve/corosync.conf" >/dev/null 2>&1; then
    wb_avert "/etc/pve/corosync.conf contient déjà expected_votes : configuration inattendue"
    return 1
  fi
  m09_ha_geler E35
}

_mE35_une() {
  local n="$1" rc=0 h
  m09_ecrire E35 injecte 1
  case "$n" in
    1)
      for h in hv02 hv03; do
        m09_exec "$h" >/dev/null <<'EOF' || { rc=$?; break; }
table_poser <<'NFT'
  chain entree {
    type filter hook input priority -5; policy accept;
    udp dport 5404-5412 counter drop comment "InfoGer : ports non documentes"
  }
NFT
EOF
      done
      ;;
    2)
      m09_exec hv01 >/dev/null <<'EOF' || rc=$?
f=/etc/pve/corosync.conf
garder "$f"
t="$(mktemp)"
cat "$f" >"$t"
# expected_votes après « provider: corosync_votequorum », dans la section quorum
perl -0pi -e 's/^(\s*)(provider:\s*corosync_votequorum[^\n]*\n)/$1$2$1expected_votes: 7\n/m or exit 10' "$t" || { rm -f "$t"; exit 10; }
version_corosync_plus "$t"
pve_ecrire_corosync "$t" || { rm -f "$t"; exit 1; }
rm -f "$t"
pose "$f"
journal "corosync.conf : expected_votes: 7 ajouté (config_version incrémentée)"
EOF
      ;;
    3)
      for h in hv02 hv03; do
        m09_exec "$h" >/dev/null <<'EOF' || { rc=$?; break; }
f=/etc/corosync/authkey
[ -f "$f" ] || exit 10
b="$WB_DIR/$WB_EX.authkey.orig"
[ -f "$b" ] || cp -a "$f" "$b"
head -c 256 /dev/urandom >"$f.neuve" && chmod 400 "$f.neuve" && mv "$f.neuve" "$f"
pose "$f"
systemctl restart corosync
journal "authkey de corosync remplacée par une clé aléatoire, corosync redémarré"
EOF
      done
      ;;
  esac
  ((rc == 0)) || { _e35_defaire "$n"; return "$rc"; }
  if ! m09_attendre 60 m09_pas_quorate hv01; then
    _e35_defaire "$n"
    return 10
  fi
}

# _e35_quorum_force — rend le quorum à la partition de hv01 le temps d'écrire dans /etc/pve
#   (votes attendus remis à 3 en mémoire : aucun effet si le quorum est déjà là).
_e35_quorum_force() {
  m09_quorate hv01 || m09_ssh hv01 "corosync-quorumtool -e 3 >/dev/null 2>&1 || pvecm expected 3" >/dev/null 2>&1 || true
  m09_attendre 30 m09_quorate hv01 || true
}

# _e35_defaire N — retire la variante N (annulation, ou variante sans effet).
_e35_defaire() {
  local h
  case "$1" in
    1)
      for h in hv02 hv03; do
        m09_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (table nftables)"
table_retirer
EOF
      done
      ;;
    2)
      _e35_quorum_force
      m09_exec hv01 >/dev/null <<'EOF' || wb_avert "annulation incomplète (corosync.conf) : retire expected_votes de /etc/pve/corosync.conf et incrémente config_version"
f=/etc/pve/corosync.conf
b="$WB_DIR/$WB_EX.$(_cle "$f")"
[ -f "$b.pose" ] || exit 0
if grep -Eq '^[[:space:]]*expected_votes:[[:space:]]*7[[:space:]]*$' "$f"; then
  # On ne remet pas l'ancien fichier (config_version plus basse : refusée) : on retire la ligne.
  t="$(mktemp)"
  cat "$f" >"$t"
  perl -ni -e 'print unless /^\s*expected_votes:\s*7\s*$/' "$t"
  version_corosync_plus "$t"
  pve_ecrire_corosync "$t" && journal "annulation : expected_votes retiré de corosync.conf"
  rm -f "$t"
else
  journal "annulation : expected_votes déjà retiré (réparation), laissé tel quel"
fi
rm -f "$b".*
EOF
      ;;
    3)
      for h in hv02 hv03; do
        m09_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (authkey)"
f=/etc/corosync/authkey
b="$WB_DIR/$WB_EX.authkey.orig"
[ -f "$b" ] || exit 0
if encore_pose "$f"; then
  cp -a "$b" "$f"
  systemctl restart corosync
  journal "annulation : authkey d'origine remise, corosync redémarré"
else
  journal "annulation : authkey modifiée depuis l'injection (réparation), laissée telle quelle"
fi
rm -f "$b" "$WB_DIR/$WB_EX.$(_cle "$f").pose"
EOF
      done
      ;;
  esac
}

_e35_injecter() {
  _e35_precondition || return 1
  m09_essayer E35 3 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }

verifier_E35() {
  ! m09_quorate hv01
}

annuler_E35() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e35_defaire "$WB_VAR" ;;
    *) _e35_defaire 1; _e35_defaire 3; _e35_defaire 2 ;;
  esac
  # Le quorum revient en quelques secondes ; la HA ne se réarme qu'avec le quorum.
  local n
  if [[ -n "$(m09_lire E35 injecte)" ]]; then
    for n in "${_M09_NOEUDS[@]}"; do
      m09_attendre 60 m09_quorate "$n" || wb_avert "$n n'a pas retrouvé le quorum après l'annulation : lab/bin/check 09 35"
    done
    m09_effacer E35 injecte
  fi
  m09_ha_rearmer E35
}

resume_E35() {
  echo "Plus aucune action possible sur le cluster hv-par1 : « cluster not ready - no quorum? (500) » sur tous les nœuds."
}

symptome_E35() {
  wb_symptome "Ticket INC-3641 — De : Nadia Roussel" \
    "Depuis 7 h 05, plus aucune action n'aboutit sur le cluster hv-par1 : démarrer, arrêter ou" \
    "modifier une VM échoue avec « cluster not ready - no quorum? (500) », quel que soit le nœud" \
    "sur lequel on se connecte. L'interface affiche les autres nœuds en rouge ou avec un point" \
    "d'interrogation. Les VMs qui tournaient tournent toujours. Rien dans le calendrier des" \
    "changements ; Lucas « n'a rien touché, juste appliqué des consignes d'InfoGér hier soir »." \
    "" \
    "Note : l'injection a désarmé la pile HA (mode freeze) pour éviter la clôture des nœuds." \
    "Temps cible : 45 min. Contrôle : lab/bin/check 09 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E35 3 "$@"; }
fi
