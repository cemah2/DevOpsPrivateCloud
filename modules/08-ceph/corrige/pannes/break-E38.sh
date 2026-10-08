# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M08-E38 « Panne : les moniteurs perdent le quorum »
#
# Cible : un (ou deux) nœuds MON autres que le nœud admin (WB_CEPH_ADMIN, ceph01 par défaut).
# Variantes :
#   1. horloge décalée sur un nœud MON : chronyd arrêté, horloge avancée de 150 s, MON relancé
#      (élection et contrôle d'horloge) → MON_CLOCK_SKEW, MON qui sort du quorum ou le fait osciller ;
#   2. pare-feu : une table nftables « inet durcissement » (posée à chaud, hors firewalld) jette sur un
#      nœud tout trafic vers et depuis les ports MON (3300, 6789) d'un autre hôte → ce MON est isolé
#      (et, au bout de 15 min, les OSD de ce nœud ne joignent plus aucun MON) ;
#   3. MON arrêtés sur deux nœuds sur trois → plus de quorum : toute commande « ceph » attend.
# Rien n'est effacé (ni magasin de MON, ni monmap). Annulation : chronyd relancé et horloge
# resynchronisée, table nftables retirée, MON relancés — seulement si c'est encore cassé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

# _e38_autres — nœuds MON autres que le nœud admin, dans un ordre aléatoire.
_e38_autres() {
  local h
  for h in "${_M08_NOEUDS[@]}"; do
    [[ "$h" != "$_M08_ADMIN" ]] && printf '%s\n' "$h"
  done | shuf
}

# _e38_hors_quorum HÔTE — 0 si mon.HÔTE n'est pas dans le quorum, ou si l'horloge est signalée.
_e38_hors_quorum() {
  local j
  j="$(m08_ceph status -f json 2>/dev/null)" || return 1
  jq -e --arg m "$1" '(.quorum_names | index($m) | not) or (.health.checks | has("MON_CLOCK_SKEW"))' >/dev/null 2>&1 <<<"$j"
}

# _e38_sans_quorum — 0 si le nœud admin n'obtient aucune réponse des MON (pas de quorum).
_e38_sans_quorum() {
  ! m08_admin >/dev/null 2>&1 <<'EOF'
ceph_sh 'timeout 30 ceph --connect-timeout 15 status >/dev/null'
EOF
}

_mE38_une() {
  local n="$1" h1 h2 rc=0
  { read -r h1; read -r h2; } < <(_e38_autres)
  [[ -n "${h1:-}" ]] || return 10
  case "$n" in
    1)
      m08_wb_exec "$h1" H="$h1" >/dev/null <<'EOF' || rc=$?
systemctl is-active -q chronyd || exit 10
[ -n "$(demons_ mon)" ] || exit 10
systemctl stop chronyd
touch "$WB_DIR/M08-E38.chrony"
date -s "@$(( $(date +%s) + 150 ))" >/dev/null
journal "chronyd arrêté, horloge avancée de 150 s"
systemctl restart "$(unite_ "mon.$H")"
EOF
      ((rc == 0)) || return "$rc"
      m08_ecrire E38 cible "$h1"
      m08_attendre 120 _e38_hors_quorum "$h1" || { _e38_defaire 1; return 10; }
      ;;
    2)
      m08_wb_exec "$h1" IP="${_M08_IP_PUB[$h1]}" >/dev/null <<'EOF' || rc=$?
command -v nft >/dev/null || exit 10
nft list table inet durcissement >/dev/null 2>&1 && exit 10
nft -f - <<NFT || exit 1
table inet durcissement {
  comment "Durcissement InfoGer - ports d'administration"
  chain entree {
    type filter hook input priority -50; policy accept;
    ip saddr != $IP tcp dport { 3300, 6789 } counter drop comment "filtrage ports Ceph"
  }
  chain sortie {
    type filter hook output priority -50; policy accept;
    ip daddr != $IP tcp dport { 3300, 6789 } counter drop comment "filtrage ports Ceph"
  }
}
NFT
touch "$WB_DIR/M08-E38.nft"
journal "table nftables inet durcissement posée à chaud (ports 3300 et 6789)"
EOF
      ((rc == 0)) || return "$rc"
      m08_ecrire E38 cible "$h1"
      m08_attendre 120 _e38_hors_quorum "$h1" || { _e38_defaire 2; return 10; }
      ;;
    3)
      [[ -n "${h2:-}" ]] || return 10
      m08_ecrire E38 cible "$h1 $h2"
      m08_arreter "$h1" "mon.$h1" >/dev/null || { _e38_defaire 3; return 10; }
      m08_arreter "$h2" "mon.$h2" >/dev/null || { _e38_defaire 3; return 10; }
      m08_attendre 60 _e38_sans_quorum || { _e38_defaire 3; return 10; }
      ;;
  esac
  m08_journal E38 "variante $n posée ($(m08_lire E38 cible))"
}

# _e38_defaire N — retire la variante N si elle est encore en place.
_e38_defaire() {
  local h
  case "$1" in
    1)
      for h in $(m08_lire E38 cible); do
        m08_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (chrony)"
[ -f "$WB_DIR/M08-E38.chrony" ] || exit 0
if ! systemctl is-active -q chronyd; then
  systemctl start chronyd
  sleep 5
  chronyc -a makestep >/dev/null 2>&1 || true
  journal "annulation : chronyd relancé, horloge resynchronisée"
fi
rm -f "$WB_DIR/M08-E38.chrony"
EOF
      done
      ;;
    2)
      for h in $(m08_lire E38 cible); do
        m08_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (nftables)"
[ -f "$WB_DIR/M08-E38.nft" ] || exit 0
if nft list table inet durcissement >/dev/null 2>&1; then
  nft delete table inet durcissement && journal "annulation : table inet durcissement retirée"
fi
rm -f "$WB_DIR/M08-E38.nft"
EOF
      done
      ;;
    3)
      for h in $(m08_lire E38 cible); do
        m08_relancer "$h" "mon.$h" >/dev/null
      done
      ;;
  esac
}

_e38_injecter() {
  m08_preparer || return 1
  m08_essayer E38 3 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }

verifier_E38() {
  local h
  read -r h _ <<<"$(m08_lire E38 cible)"
  [[ -n "${h:-}" ]] || return 1
  case "$WB_VAR" in
    3) _e38_sans_quorum ;;
    *) _e38_hors_quorum "$h" ;;
  esac
}

annuler_E38() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e38_defaire "$WB_VAR" ;;
    *) _e38_defaire 3; _e38_defaire 2; _e38_defaire 1 ;;
  esac
  m08_journal E38 "annulation"
  rm -rf -- "$(m08_etat E38)"
}

resume_E38() {
  case "${WB_VAR:-}" in
    3) echo "Les commandes « ceph » restent sans réponse sur le nœud admin ; les clients se figent." ;;
    *) echo "ceph -s signale un moniteur hors quorum (ou qui entre et sort du quorum)." ;;
  esac
}

symptome_E38() {
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-3544 — De : Nadia Roussel — priorité P1" \
        "Plus rien ne répond côté stockage : « ceph -s » sur ceph01 reste bloqué puis échoue," \
        "le tableau de bord ne charge plus, la sonde de cephcli01 se fige. InfoGér a « redémarré" \
        "des services pour appliquer des mises à jour » sur les nœuds Ceph cette nuit." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 08 38"
      ;;
    *)
      wb_symptome "Ticket INC-3544 — De : Nadia Roussel" \
        "ceph-par1 est en HEALTH_WARN depuis cette nuit : la supervision parle d'un moniteur hors" \
        "du quorum, et les commandes « ceph » sont parfois lentes à répondre. Rien n'a changé" \
        "côté Ceph, d'après InfoGér, qui a seulement « durci » quelques serveurs." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 08 38"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E38 3 "$@"; }
fi
