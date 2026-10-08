# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M08-E42 « Panne : le cluster est lent »
#
# Variantes :
#   1. « MTU cassé » sur le réseau cluster d'un nœud : le lab ne peut pas toucher vmbr1 (pve01), on
#      simule donc l'équipement intermédiaire resté à 1500 octets sur le nœud lui-même : délestages
#      de segmentation coupés sur ens19 (ethtool -K gro/gso/tso off, pour que les trames soient vues
#      à leur vraie taille) et table nftables « inet medisphere_qos » qui jette en silence les
#      trames de plus de 1500 octets sur ens19 → trou noir de PMTU : les petits paquets passent, les
#      gros non ; battements de cœur (2000 octets) perdus, OSD qui oscillent, requêtes lentes ;
#   2. ordonnanceur mClock : profil « custom » avec une limite client à 1 % de la capacité des OSD
#      (osd_mclock_scheduler_client_lim) → débit client écrasé ;
#   3. limitation de débit sur ens19 d'un nœud (tc tbf à 4 Mbit/s ; à défaut, règle nftables de
#      limitation) → réplication lente, latence des écritures.
# Aucune donnée touchée. Valeurs d'origine (délestages, réglages mClock) sauvegardées ; l'annulation
# ne rétablit que ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

_e42_cible() {
  local h
  for h in "${_M08_NOEUDS[@]}"; do
    [[ "$h" != "$_M08_ADMIN" ]] && printf '%s\n' "$h"
  done | shuf -n 1
}

# _e42_gros_paquets_bloques HÔTE — depuis le nœud admin, un ping de 8972 octets sans fragmentation
# vers l'adresse cluster de HÔTE échoue alors qu'un ping de 1000 octets passe.
_e42_gros_paquets_bloques() {
  m08_admin IP="${_M08_IP_CLU[$1]}" >/dev/null 2>&1 <<'EOF'
ping -c 2 -W 2 -M do -s 1000 "$IP" >/dev/null 2>&1 || exit 1
! ping -c 2 -W 2 -M do -s 8972 "$IP" >/dev/null 2>&1
EOF
}

# _e42_reglage NOM — valeur d'un réglage dans la base de configuration (section osd), vide si absent.
_e42_reglage() {
  m08_ceph config dump -f json 2>/dev/null | jq -r --arg n "$1" '.[] | select(.section == "osd" and .name == $n) | .value' | head -n 1
}

_mE42_une() {
  local n="$1" h rc=0
  h="$(_e42_cible)"
  case "$n" in
    1)
      m08_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
command -v ethtool >/dev/null && command -v nft >/dev/null || exit 10
ip link show ens19 >/dev/null 2>&1 || exit 10
nft list table inet medisphere_qos >/dev/null 2>&1 && exit 10
ethtool -k ens19 | sed -nE 's/^(generic-receive-offload|generic-segmentation-offload|tcp-segmentation-offload): (on|off).*/\1 \2/p' >"$WB_DIR/M08-E42.ethtool"
ethtool -K ens19 gro off gso off tso off 2>/dev/null || true
nft -f - <<'NFT' || exit 1
table inet medisphere_qos {
  comment "Profil reseau stockage (InfoGer)"
  chain entree {
    type filter hook input priority -50; policy accept;
    iifname "ens19" meta length > 1500 drop
  }
  chain sortie {
    type filter hook output priority -50; policy accept;
    oifname "ens19" meta length > 1500 drop
  }
}
NFT
journal "délestages de ens19 coupés, table inet medisphere_qos posée (trames > 1500 jetées)"
EOF
      ((rc == 0)) || return "$rc"
      m08_ecrire E42 cible "$h"
      m08_attendre 30 _e42_gros_paquets_bloques "$h" || { _e42_defaire 1; return 10; }
      ;;
    2)
      m08_ecrire E42 profil "$(_e42_reglage osd_mclock_profile)"
      m08_ecrire E42 lim "$(_e42_reglage osd_mclock_scheduler_client_lim)"
      m08_ceph config set osd osd_mclock_profile custom >/dev/null 2>&1 || return 1
      m08_ceph config set osd osd_mclock_scheduler_client_lim 0.01 >/dev/null 2>&1 || { _e42_defaire 2; return 10; }
      [[ "$(m08_ceph config get osd.0 osd_mclock_scheduler_client_lim 2>/dev/null | tr -d '[:space:]')" =~ ^0\.010*$ ]] \
        || { _e42_defaire 2; return 10; }
      ;;
    3)
      m08_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
ip link show ens19 >/dev/null 2>&1 || exit 10
if command -v tc >/dev/null && tc qdisc add dev ens19 root tbf rate 4mbit burst 64kb latency 400ms 2>/dev/null; then
  echo tc >"$WB_DIR/M08-E42.limite"
  journal "file tbf 4 Mbit/s posée à la racine de ens19"
elif command -v nft >/dev/null && ! nft list table inet medisphere_qos >/dev/null 2>&1; then
  nft -f - <<'NFT' || exit 1
table inet medisphere_qos {
  comment "Profil reseau stockage (InfoGer)"
  chain sortie {
    type filter hook output priority -50; policy accept;
    oifname "ens19" limit rate over 512 kbytes/second drop
  }
}
NFT
  echo nft >"$WB_DIR/M08-E42.limite"
  journal "limitation nftables 512 Ko/s en sortie de ens19 (tc indisponible)"
else
  exit 10
fi
EOF
      ((rc == 0)) || return "$rc"
      m08_ecrire E42 cible "$h"
      ;;
  esac
  m08_journal E42 "variante $n posée ${h:+sur $h}"
}

# _e42_defaire N — retire la variante N si elle est encore en place.
_e42_defaire() {
  local h prof lim
  h="$(m08_lire E42 cible)"
  case "$1" in
    1)
      [[ -n "$h" ]] || return 0
      m08_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (réseau cluster)"
if nft list table inet medisphere_qos >/dev/null 2>&1 && [ -f "$WB_DIR/M08-E42.ethtool" ]; then
  nft delete table inet medisphere_qos && journal "annulation : table inet medisphere_qos retirée"
fi
if [ -f "$WB_DIR/M08-E42.ethtool" ]; then
  while read -r f v; do
    case "$f" in
      generic-receive-offload) o=gro ;;
      generic-segmentation-offload) o=gso ;;
      tcp-segmentation-offload) o=tso ;;
      *) continue ;;
    esac
    # Seulement si l'apprenant ne l'a pas déjà changé.
    if ethtool -k ens19 | grep -q "^$f: off" && [ "$v" = on ]; then ethtool -K ens19 "$o" on 2>/dev/null || true; fi
  done <"$WB_DIR/M08-E42.ethtool"
  rm -f "$WB_DIR/M08-E42.ethtool"
  journal "annulation : délestages de ens19 rétablis"
fi
EOF
      ;;
    2)
      prof="$(m08_lire E42 profil)"
      lim="$(m08_lire E42 lim)"
      if [[ "$(_e42_reglage osd_mclock_scheduler_client_lim)" == 0.01* ]]; then
        if [[ -n "$lim" ]]; then
          m08_ceph config set osd osd_mclock_scheduler_client_lim "$lim" >/dev/null 2>&1 || true
        else
          m08_ceph config rm osd osd_mclock_scheduler_client_lim >/dev/null 2>&1 || true
        fi
      fi
      if [[ "$(_e42_reglage osd_mclock_profile)" == custom && "$prof" != custom ]]; then
        if [[ -n "$prof" ]]; then
          m08_ceph config set osd osd_mclock_profile "$prof" >/dev/null 2>&1 || true
        else
          m08_ceph config rm osd osd_mclock_profile >/dev/null 2>&1 || true
        fi
      fi
      ;;
    3)
      [[ -n "$h" ]] || return 0
      m08_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (limitation de débit)"
f="$WB_DIR/M08-E42.limite"
[ -f "$f" ] || exit 0
if [ "$(cat "$f")" = tc ]; then
  if tc qdisc show dev ens19 | grep -q '^qdisc tbf'; then tc qdisc del dev ens19 root && journal "annulation : file tbf retirée"; fi
elif nft list table inet medisphere_qos >/dev/null 2>&1; then
  nft delete table inet medisphere_qos && journal "annulation : table inet medisphere_qos retirée"
fi
rm -f "$f"
EOF
      ;;
  esac
}

_e42_injecter() {
  m08_preparer || return 1
  m08_essayer E42 3 "$1"
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }

verifier_E42() {
  local h
  h="$(m08_lire E42 cible)"
  case "$WB_VAR" in
    1) _e42_gros_paquets_bloques "$h" ;;
    2) [[ "$(_e42_reglage osd_mclock_scheduler_client_lim)" == 0.01* ]] ;;
    3)
      m08_wb_exec "$h" >/dev/null 2>&1 <<'EOF'
tc qdisc show dev ens19 2>/dev/null | grep -q '^qdisc tbf' || nft list table inet medisphere_qos >/dev/null 2>&1
EOF
      ;;
  esac
}

annuler_E42() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e42_defaire "$WB_VAR" ;;
    *) _e42_defaire 3; _e42_defaire 2; _e42_defaire 1 ;;
  esac
  m08_journal E42 "annulation"
  rm -rf -- "$(m08_etat E42)"
}

resume_E42() {
  echo "Le stockage est devenu très lent (latences d'écriture multipliées, requêtes lentes signalées)."
}

symptome_E42() {
  wb_symptome "Ticket INC-3548 — De : Julien Petit" \
    "Depuis hier soir, tout ce qui touche au stockage Ceph est très lent : la sonde de cephcli01" \
    "met des secondes à écrire quelques octets, nos essais de charge sur RBD ont des latences" \
    "multipliées par dix ou plus, et la supervision a vu passer des « slow ops ». Rien de cassé" \
    "en apparence. InfoGér a livré hier « un profil réseau et des optimisations Ceph »." \
    "Mesure avant et après : je veux des chiffres, pas une impression." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 08 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E42 3 "$@"; }
fi
