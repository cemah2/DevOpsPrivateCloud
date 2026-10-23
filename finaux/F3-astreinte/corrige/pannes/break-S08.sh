# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-S08.sh — F3-S08 « Mercredi : le stockage ralentit tout » (ceph-par1)
#
# Contrôle préalable : lab sain (Ceph HEALTH_OK compris), sauvegarde CNPG de prod « completed » de moins
# de 26 h (les volumes de mediagenda-db prod sont dans k8s-rbd). Jamais de perte de PG : un seul OSD
# touché à la fois, aucun OSD détruit ni marqué « out » par la panne, aucune donnée supprimée.
#   1. « Intervention » de Lucas : drapeau noout posé, puis un OSD (classe ssd, nœud tiré au hasard)
#      arrêté par l'orchestrateur (ceph orch daemon stop) : PG dégradés, et noout empêche la
#      reconstruction ; HEALTH_WARN durable. Annulation : OSD redémarré ; noout retiré s'il n'existait
#      pas avant la panne.
#   2. Hyperviseur : limites d'E/S QEMU (iops_rd/iops_wr = 8, mbps_rd/mbps_wr = 2) posées par « qm set »
#      sur TOUS les disques d'OSD d'une VM Ceph (pas le disque système) : les OSD de ce nœud deviennent
#      lents (slow ops, latence de commit). Définition d'origine de chaque disque gardée sur pve01
#      (/var/lib/workbook/F3-S08.disques), remise si la définition injectée est toujours en place.
#   3. Quota : « ceph osd pool set-quota k8s-rbd max_bytes » posé à la taille stockée actuelle + 1 Mio
#      (« pour figer la croissance en attendant les disques ») : le pool atteint son quota, POOL_FULL,
#      les écritures RBD se bloquent (sans erreur ni perte : elles attendent). Annulation : quota d'origine.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

_S08_ADMIN="${WB_F3_CEPH_ADMIN:-${WB_CEPH_ADMIN:-ceph01}}"
_S08_POOL="${WB_F3_S08_POOL:-k8s-rbd}"
read -r -a _S08_VMS <<<"${WB_F3_S08_CEPH_VMS:-ceph01:2081 ceph02:2082 ceph03:2083}"

# _s08_ceph "ARGUMENTS" — commande ceph (écriture permise) sur le nœud _admin.
_s08_ceph() {
  remote "$_S08_ADMIN" "if command -v ceph >/dev/null; then sudo -n ceph $1; else sudo -n cephadm shell -- ceph $1; fi" </dev/null 2>/dev/null
}
_s08_checks() { _s08_ceph "health detail -f json" | jq -r '.checks // {} | keys[]' 2>/dev/null; }

# --- Variante 1 : noout + un OSD arrêté --------------------------------------------------------------------

_s08_v1_poser() {
  local tree host osd flags
  flags="$(_s08_ceph "osd dump -f json" | jq -r '.flags // ""')" || return 1
  [[ ",$flags," == *",noout,"* ]] && return 10
  tree="$(_s08_ceph "osd tree -f json")" || return 1
  host="$(jq -r '[.nodes[] | select(.type == "host") | .name] | .[]' <<<"$tree" | shuf -n 1)"
  [[ -n "$host" ]] || return 10
  osd="$(jq -r --arg h "$host" '
      (.nodes[] | select(.type == "host" and .name == $h) | .children) as $c
      | [.nodes[] | select(.type == "osd" and (.id as $i | $c | index($i)) and .status == "up" and (.device_class // "") == "ssd") | .id][0] // empty' <<<"$tree")"
  [[ "$osd" =~ ^[0-9]+$ ]] || return 10
  _f3p_ecrire S08 v1-osd "$osd"
  _s08_ceph "osd set noout" >/dev/null || return 1
  _f3p_ecrire S08 v1-noout pose
  _s08_ceph "orch daemon stop osd.$osd" >/dev/null || return 1
  _f3p_journal S08 "noout posé, osd.$osd ($host) arrêté"
}
_s08_v1_constat() { local c; c="$(_s08_checks)"; grep -qx OSD_DOWN <<<"$c" && grep -qx OSDMAP_FLAGS <<<"$c"; }
_s08_v1_defaire() {
  local osd
  osd="$(_f3p_lire S08 v1-osd)"
  if [[ -n "$osd" ]]; then
    _s08_ceph "orch daemon start osd.$osd" >/dev/null || wb_avert "osd.$osd à redémarrer : ceph orch daemon start osd.$osd"
    _f3p_journal S08 "osd.$osd redémarré"
  fi
  if [[ -n "$(_f3p_lire S08 v1-noout)" ]]; then
    _s08_ceph "osd unset noout" >/dev/null || wb_avert "noout à retirer : ceph osd unset noout"
    _f3p_journal S08 "noout retiré"
  fi
  _f3p_oublier S08 v1-osd
  _f3p_oublier S08 v1-noout
}

# --- Variante 2 : disques d'OSD bridés par l'hyperviseur ----------------------------------------------

_s08_v2_poser() {
  local paire nom vmid
  paire="$(printf '%s\n' "${_S08_VMS[@]}" | shuf -n 1)"
  IFS=: read -r nom vmid <<<"$paire"
  [[ "$vmid" =~ ^[0-9]+$ ]] || return 10
  _f3p_ecrire S08 v2-vm "$nom:$vmid"
  wb_exec "$WB_PVE_HOST" VMID="$vmid" >/dev/null 2>&1 <<'EOF'
command -v qm >/dev/null || exit 10
cfg="$(qm config "$VMID" 2>/dev/null)" || exit 10
boot="$(printf '%s\n' "$cfg" | sed -n 's/^boot: .*order=\([a-z]*[0-9]*\).*/\1/p')"
[ -n "$boot" ] || boot="$(printf '%s\n' "$cfg" | sed -n 's/^bootdisk: //p')"
[ -n "$boot" ] || exit 10
: > "$WB_DIR/F3-S08.disques"
n=0
printf '%s\n' "$cfg" | grep -E '^(scsi|virtio|sata)[0-9]+: ' | grep -v 'media=cdrom' | while IFS= read -r ligne; do
  cle="${ligne%%:*}"; val="${ligne#*: }"
  [ "$cle" = "$boot" ] && continue
  case "$val" in *iops_*|*mbps_*) continue ;; esac
  neuf="$val,iops_rd=8,iops_wr=8,mbps_rd=2,mbps_wr=2"
  qm set "$VMID" "--$cle" "$neuf" >/dev/null 2>&1 || continue
  # Proxmox réécrit la définition dans son ordre canonique : on garde la forme RELUE, pour que
  # l'annulation la reconnaisse (comparaison exacte).
  neuf="$(qm config "$VMID" | sed -n "s/^$cle: //p")"
  printf '%s\t%s\t%s\n' "$cle" "$val" "$neuf" >> "$WB_DIR/F3-S08.disques"
  journal "VM $VMID : $cle bridé (iops 8, 2 Mo/s)"
done
[ -s "$WB_DIR/F3-S08.disques" ] || exit 10
EOF
}
_s08_v2_osds() {
  local nom
  nom="$(_f3p_lire S08 v2-vm | cut -d: -f1)"
  _s08_ceph "osd tree -f json" | jq -r --arg h "$nom" '
    (.nodes[] | select(.type == "host" and (.name | startswith($h))) | .children) as $c | $c[]' 2>/dev/null
}
_s08_v2_constat() {
  local osds max
  grep -qx SLOW_OPS <<<"$(_s08_checks)" && return 0
  osds="$(_s08_v2_osds | paste -sd, -)"
  [[ -n "$osds" ]] || return 1
  max="$(_s08_ceph "osd perf -f json" | jq -r --argjson ids "[$osds]" '
    [(.osdstats.osd_perf_infos // .osd_perf_infos)[] | select(.id as $i | $ids | index($i)) | .perf_stats.commit_latency_ms] | max // 0' 2>/dev/null)"
  [[ "$max" =~ ^[0-9]+$ ]] && ((max >= 100))
}
_s08_v2_defaire() {
  local vmid
  vmid="$(_f3p_lire S08 v2-vm | cut -d: -f2)"
  [[ -n "$vmid" ]] || return 0
  wb_exec "$WB_PVE_HOST" VMID="$vmid" >/dev/null 2>&1 <<'EOF' || wb_avert "disques de la VM $vmid à vérifier sur pve01 (qm config $vmid)"
f="$WB_DIR/F3-S08.disques"
[ -f "$f" ] || exit 0
while IFS="$(printf '\t')" read -r cle val neuf; do
  cur="$(qm config "$VMID" | sed -n "s/^$cle: //p")"
  if [ "$cur" = "$neuf" ]; then
    qm set "$VMID" "--$cle" "$val" >/dev/null 2>&1 && journal "VM $VMID : $cle rétabli"
  else
    journal "annulation : $cle de la VM $VMID modifié depuis la panne, laissé tel quel"
  fi
done < "$f"
rm -f "$f"
exit 0
EOF
  _f3p_oublier S08 v2-vm
}

# --- Variante 3 : quota du pool atteint --------------------------------------------------------------------

_s08_v3_poser() {
  local q stored inj
  q="$(_s08_ceph "osd pool get-quota $_S08_POOL -f json" | jq -r '.quota_max_bytes // empty')" || return 10
  [[ "$q" == 0 ]] || return 10
  stored="$(_s08_ceph "df -f json" | jq -r --arg p "$_S08_POOL" '.pools[] | select(.name == $p) | .stats.stored // .stats.bytes_used // empty')"
  [[ "$stored" =~ ^[0-9]+$ ]] && ((stored > 0)) || return 10
  inj=$((stored + 1048576))
  _f3p_ecrire S08 v3-quota "$inj"
  _s08_ceph "osd pool set-quota $_S08_POOL max_bytes $inj" >/dev/null || return 1
  _f3p_journal S08 "quota de $_S08_POOL : $inj octets (stocké : $stored)"
}
_s08_v3_constat() { grep -qx POOL_FULL <<<"$(_s08_checks)"; }
_s08_v3_defaire() {
  local inj q
  inj="$(_f3p_lire S08 v3-quota)"
  [[ -n "$inj" ]] || return 0
  q="$(_s08_ceph "osd pool get-quota $_S08_POOL -f json" | jq -r '.quota_max_bytes // empty')" || q=""
  if [[ "$q" == "$inj" ]]; then
    _s08_ceph "osd pool set-quota $_S08_POOL max_bytes 0" >/dev/null || wb_avert "quota à retirer : ceph osd pool set-quota $_S08_POOL max_bytes 0"
    _f3p_journal S08 "quota de $_S08_POOL retiré"
  fi
  _f3p_oublier S08 v3-quota
}

# --- Mécanique commune ------------------------------------------------------------------------------------

_f3p_S08_une() {
  case "$1" in
    1) _s08_v1_poser || return $?; _f3p_attendre 180 _s08_v1_constat || return 10 ;;
    2) _s08_v2_poser || return $?; _f3p_attendre 300 _s08_v2_constat || return 10 ;;
    3) _s08_v3_poser || return $?; _f3p_attendre 300 _s08_v3_constat || return 10 ;;
  esac
}
_f3p_S08_defaire() {
  case "$1" in
    1) _s08_v1_defaire ;;
    2) _s08_v2_defaire ;;
    3) _s08_v3_defaire ;;
  esac
}

_s08_injecter() {
  _f3p_preparer S08 shuf || return 1
  _f3p_sauvegarde_prod || return 1
  _f3p_essayer S08 3 "$1"
}

panne_S08_v1() { _s08_injecter 1; }
panne_S08_v2() { _s08_injecter 2; }
panne_S08_v3() { _s08_injecter 3; }

verifier_S08() {
  case "$(_f3p_lire S08 variante)" in
    1) _s08_v1_constat ;;
    2) _s08_v2_constat ;;
    3) _s08_v3_constat ;;
    *) return 1 ;;
  esac
}

annuler_S08() {
  local v
  for v in 3 2 1; do _f3p_S08_defaire "$v" || true; done
  _f3p_oublier S08 variante
}

resume_S08() { echo "tout est lent : stockage Ceph en difficulté"; }

symptome_S08() {
  _f3p_symptome S08 INC-5908 "Ticket INC-5908 — De : Claire Morel — mercredi 9 h 30" \
    "« Tout le monde se plaint en même temps : Grafana met une éternité, les journaux arrivent dans" \
    "Loki avec des minutes de retard, Julien dit que la recette rame et que les déploiements traînent," \
    "et je viens d'avoir un appel du support pour la prod. Rien n'a été livré cette nuit. Trouve ce qui" \
    "est commun à tout ça. Je veux un premier message d'état dans 15 minutes. »" \
    "Temps cible : 1 h 30."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S08 3 "$@"; }
fi
