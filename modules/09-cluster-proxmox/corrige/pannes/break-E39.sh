# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M09-E39 « Panne : les VMs se figent »
#
# Ceph hyperconvergé du cluster (pveceph, M09-E10/E28), pool du stockage ceph-vm (size 3, min_size 2).
# Variantes :
#   1. les OSD de hv02 et de hv03 arrêtés ET désactivés (« économie de mémoire » appliquée la veille) →
#      une seule copie de chaque PG : PG inactifs (undersized+degraded+peered), E/S bloquées ;
#   2. trou noir MTU sur le réseau cluster de hv03 : table nftables « inet infoger_durcissement » qui
#      jette les paquets de plus de 1500 octets de/vers 10.10.31.0/24 → petits paquets OK, gros paquets
#      (battements de cœur des OSD, 2000 octets ; réplication) perdus → OSD de hv03 marqués down puis
#      « wrongly marked me down », opérations lentes, E/S figées par moments ;
#   3. « maintenance » de hv03 : noout posé, OSD de hv03 arrêtés (pas désactivés), ET min_size du pool
#      relevé à 3 (« plus sûr », dit Lucas) → deux copies sur trois : PG inactifs.
# Sauvegardes : état local ~/.local/state/workbook/M09-E39/ (min_size d'origine, OSD touchés, noout).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

# _e39_pool — pool RBD du stockage ceph-vm (propriété « pool » de storage.cfg, « rbd » par défaut).
_e39_pool() {
  local p
  p="$(m09_exec hv01 2>/dev/null <<'EOF'
stockage_section ceph-vm pool
EOF
)" || true
  printf '%s\n' "${p:-rbd}"
}

# _e39_osd NŒUD — identifiants des OSD du nœud.
_e39_osd() {
  m09_ssh hv01 "ceph osd ls-tree $1" 2>/dev/null | tr '\n' ' '
}

_e39_pg_inactifs() {
  m09_ssh hv01 "timeout 20 ceph health detail" 2>/dev/null | grep -Eq 'PG_AVAILABILITY|inactive'
}

_e39_trou_mtu() {
  ! m09_ssh hv01 "ping -M do -s 8972 -c 2 -W 2 ${_M09_STOCLU[hv03]}" >/dev/null 2>&1 \
    && m09_ssh hv01 "ping -c 2 -W 2 ${_M09_STOCLU[hv03]}" >/dev/null 2>&1
}

_e39_precondition() {
  m09_cluster_sain || return 1
  local pool sz
  if ! m09_ssh hv01 "timeout 20 ceph health" 2>/dev/null | grep -q '^HEALTH_OK'; then
    wb_avert "Ceph n'est pas HEALTH_OK avant la panne (ceph health detail sur hv01) : lab/bin/check 09 39"
    return 1
  fi
  pool="$(_e39_pool)"
  sz="$(m09_ssh hv01 "ceph osd pool get $pool size; ceph osd pool get $pool min_size" 2>/dev/null | tr '\n' ' ')"
  if [[ "$sz" != *"size: 3"*"min_size: 2"* ]]; then
    wb_avert "pool $pool : size 3 / min_size 2 attendus (trouvé : ${sz:-rien})"
    return 1
  fi
  if ! m09_ssh hv01 "ping -M do -s 8972 -c 2 -W 2 ${_M09_STOCLU[hv03]}" >/dev/null 2>&1; then
    wb_avert "le réseau cluster de Ceph ne passe déjà pas les trames de 9000 octets vers hv03"
    return 1
  fi
  if m09_ssh hv03 "nft list table inet $_M09_TABLE" >/dev/null 2>&1; then
    wb_avert "hv03 : une table nftables inet $_M09_TABLE existe déjà (panne précédente non close ?)"
    return 1
  fi
  m09_ecrire E39 pool "$pool"
}

_mE39_une() {
  local n="$1" rc=0 h ids pool
  pool="$(m09_lire E39 pool)"
  case "$n" in
    1)
      for h in hv02 hv03; do
        ids="$(_e39_osd "$h")"
        [[ -n "${ids// /}" ]] || { rc=10; break; }
        m09_ecrire E39 "osd-$h" "$ids"
        m09_ssh "$h" "for i in $ids; do systemctl disable --now ceph-osd@\$i >/dev/null 2>&1; done" >/dev/null 2>&1 || true
        m09_journal E39 "$h : OSD $ids arrêtés et désactivés"
      done
      ;;
    2)
      m09_exec hv03 >/dev/null <<'EOF' || rc=$?
table_poser <<'NFT'
  chain entree {
    type filter hook input priority -5; policy accept;
    ip saddr 10.10.31.0/24 meta length > 1500 counter drop comment "InfoGer : limitation de taille"
  }
  chain sortie {
    type filter hook output priority -5; policy accept;
    ip daddr 10.10.31.0/24 meta length > 1500 counter drop comment "InfoGer : limitation de taille"
  }
NFT
EOF
      ;;
    3)
      if ! m09_ssh hv01 "ceph osd dump" 2>/dev/null | grep -Eq '^flags .*noout'; then
        m09_ssh hv01 "ceph osd set noout" >/dev/null 2>&1 && m09_ecrire E39 noout 1
      fi
      ids="$(_e39_osd hv03)"
      [[ -n "${ids// /}" ]] || rc=10
      if ((rc == 0)); then
        m09_ecrire E39 osd-hv03-arret "$ids"
        m09_ssh hv03 "for i in $ids; do systemctl stop ceph-osd@\$i; done" >/dev/null 2>&1 || true
        m09_ssh hv01 "ceph osd pool set $pool min_size 3" >/dev/null 2>&1 || rc=1
        ((rc == 0)) && m09_ecrire E39 min_size 2
        m09_journal E39 "noout, OSD $ids de hv03 arrêtés, min_size de $pool passé à 3"
      fi
      ;;
  esac
  ((rc == 0)) || { _e39_defaire "$n"; return "$rc"; }
  local ok=0
  case "$n" in
    1 | 3) m09_attendre 90 _e39_pg_inactifs && ok=1 ;;
    2) m09_attendre 20 _e39_trou_mtu && ok=1 ;;
  esac
  if ((ok == 0)); then
    _e39_defaire "$n"
    return 10
  fi
}

_e39_defaire() {
  local h ids pool
  pool="$(m09_lire E39 pool)"
  case "$1" in
    1)
      for h in hv02 hv03; do
        ids="$(m09_lire E39 "osd-$h")"
        [[ -n "$ids" ]] || continue
        # Seuls les OSD encore désactivés (état posé) sont relancés ; les autres ont été réparés.
        m09_ssh "$h" "for i in $ids; do systemctl is-enabled -q ceph-osd@\$i || systemctl enable --now ceph-osd@\$i >/dev/null 2>&1; systemctl is-active -q ceph-osd@\$i || systemctl start ceph-osd@\$i; done" >/dev/null 2>&1 || true
        m09_effacer E39 "osd-$h"
        m09_journal E39 "annulation : OSD $ids de $h réactivés (si encore désactivés)"
      done
      ;;
    2)
      m09_exec hv03 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv03 (table nftables)"
table_retirer
EOF
      ;;
    3)
      if [[ -n "$(m09_lire E39 min_size)" ]]; then
        if m09_ssh hv01 "ceph osd pool get $pool min_size" 2>/dev/null | grep -q 'min_size: 3'; then
          m09_ssh hv01 "ceph osd pool set $pool min_size 2" >/dev/null 2>&1 || wb_avert "min_size de $pool non rétabli"
        fi
        m09_effacer E39 min_size
      fi
      ids="$(m09_lire E39 osd-hv03-arret)"
      if [[ -n "$ids" ]]; then
        m09_ssh hv03 "for i in $ids; do systemctl is-active -q ceph-osd@\$i || systemctl start ceph-osd@\$i; done" >/dev/null 2>&1 || true
        m09_effacer E39 osd-hv03-arret
      fi
      if [[ -n "$(m09_lire E39 noout)" ]]; then
        m09_ssh hv01 "ceph osd unset noout" >/dev/null 2>&1 || true
        m09_effacer E39 noout
      fi
      m09_journal E39 "annulation : min_size, OSD de hv03 et noout rétablis (si encore dans l'état posé)"
      ;;
  esac
}

_e39_injecter() {
  _e39_precondition || return 1
  m09_essayer E39 3 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }

verifier_E39() {
  case "${WB_VAR:-1}" in
    2) _e39_trou_mtu ;;
    *) _e39_pg_inactifs ;;
  esac
}

annuler_E39() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e39_defaire "$WB_VAR" ;;
    *) _e39_defaire 2; _e39_defaire 3; _e39_defaire 1 ;;
  esac
  m09_effacer E39 pool
}

resume_E39() {
  echo "Des VMs du cluster stockées sur ceph-vm sont figées (E/S bloquées) ; Ceph n'est plus HEALTH_OK."
}

symptome_E39() {
  wb_symptome "Ticket INC-3645 — De : Nadia Roussel" \
    "Depuis 6 h 40, plusieurs VMs du cluster hv-par1 sont figées : la console répond mal, les" \
    "invités journalisent « task … blocked for more than 120 seconds » et certains programmes" \
    "restent bloqués en écriture. Le tableau de bord Ceph de l'interface n'est plus vert." \
    "Aucune VM n'est arrêtée. Les équipes demandent si elles doivent redémarrer leurs VMs : la" \
    "réponse est non tant que tu n'as pas compris." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 09 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E39 3 "$@"; }
fi
