# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M09-E38 « Panne : la migration à chaud échoue »
#
# Invité de test : pan-mig (VMID 194), disque sur ceph-vm, démarré sur hv01 (sans système : il
# tourne dans son BIOS, ce qui suffit pour une migration à chaud). Destination demandée : hv02.
# Variantes :
#   1. second disque de 194 sur local-lvm de hv01 (« disque de travail ajouté vite fait ») ;
#   2. ISO présente seulement sur le stockage « local » de hv01 montée dans le lecteur de 194 ;
#   3. nftables DANS hv02 : table « inet infoger_durcissement » qui jette le SSH (TCP 22) venant des
#      autres nœuds (adresses MGMT, Corosync, Ceph public et cluster ; adm01 n'est pas touché) → le
#      tunnel de migration (type secure) ne s'établit plus ;
#   4. /etc/pve/datacenter.cfg : « bwlimit: migration=1 » (1 Kio/s) → la migration ne finit jamais.
# Sauvegardes : /var/lib/workbook/M09-E38.* sur hv01 (datacenter.cfg, ISO) et hv02 (table).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E38_ISO=outils-infoger-2019.iso

_e38_precondition() {
  m09_cluster_sain || return 1
  m09_vmid_libre 194 || { wb_avert "le VMID 194 (réservé aux pannes du palier 4) est déjà pris"; return 1; }
  m09_stockage_actif hv01 ceph-vm || { wb_avert "stockage ceph-vm inactif sur hv01 (M09-E10)"; return 1; }
  if m09_ssh hv02 "nft list table inet $_M09_TABLE" >/dev/null 2>&1; then
    wb_avert "hv02 : une table nftables inet $_M09_TABLE existe déjà (panne précédente non close ?)"
    return 1
  fi
  m09_vm_creer E38 194 pan-mig hv01 ceph-vm:1 || return 1
  m09_ssh hv01 "qm start 194" >/dev/null 2>&1 || { wb_avert "la VM de test 194 ne démarre pas sur hv01"; return 1; }
}

# _e38_precheck — sortie JSON du contrôle préalable de migration de 194 vers hv02.
_e38_precheck() {
  m09_json hv01 /nodes/hv01/qemu/194/migrate --target hv02
}

# _e38_ssh_vers_hv02 — depuis hv01, SSH root vers hv02 (adresse MGMT et adresse Ceph public).
_e38_ssh_vers_hv02() {
  m09_ssh hv01 "for ip in ${_M09_IP[hv02]} ${_M09_STOPUB[hv02]}; do ssh -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=hv02 root@\$ip true || exit 1; done" >/dev/null 2>&1
}

_e38_effet() {
  local j
  case "$1" in
    1 | 2)
      j="$(_e38_precheck)" || return 0
      jq -e '((.local_disks // []) | length > 0) or ((.local_resources // []) | length > 0) or ((.not_allowed_nodes // {}) | has("hv02"))' <<<"$j" >/dev/null 2>&1
      ;;
    3) ! _e38_ssh_vers_hv02 ;;
    4) m09_ssh hv01 "grep -Eq '^bwlimit:.*migration=1([,[:space:]]|\$)' /etc/pve/datacenter.cfg" >/dev/null 2>&1 ;;
  esac
}

_mE38_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m09_ssh hv01 "qm set 194 --scsi1 local-lvm:1" >/dev/null 2>&1 || rc=1
      ;;
    2)
      m09_exec hv01 ISO="$_E38_ISO" >/dev/null <<'EOF' || rc=$?
d="$(pvesm path "local:iso/$ISO" 2>/dev/null)" || exit 10
[ -n "$d" ] && [ ! -e "$d" ] || exit 10
mkdir -p "$(dirname "$d")"
head -c 4194304 /dev/zero >"$d"
printf '%s\n' "$d" >"$WB_DIR/$WB_EX.iso"
qm set 194 --ide2 "local:iso/$ISO,media=cdrom" >/dev/null || exit 1
journal "ISO $d créée sur hv01 seulement et montée dans 194"
EOF
      ;;
    3)
      local srcs
      srcs="${_M09_IP[hv01]}, ${_M09_IP[hv03]}, ${_M09_CORO[hv01]}, ${_M09_CORO[hv03]}, ${_M09_STOPUB[hv01]}, ${_M09_STOPUB[hv03]}, ${_M09_STOCLU[hv01]}, ${_M09_STOCLU[hv03]}"
      m09_exec hv02 SRCS="$srcs" >/dev/null <<'EOF' || rc=$?
table_poser <<NFT
  chain entree {
    type filter hook input priority -5; policy accept;
    ip saddr { $SRCS } tcp dport 22 counter drop comment "InfoGer : SSH inter-noeuds interdit"
  }
NFT
EOF
      ;;
    4)
      m09_exec hv01 >/dev/null <<'EOF' || rc=$?
f=/etc/pve/datacenter.cfg
garder "$f"
t="$(mktemp)"
[ -f "$f" ] && cat "$f" >"$t"
if grep -Eq '^bwlimit:.*migration=' "$t"; then
  sed -i -E '/^bwlimit:/ s/migration=[0-9]+/migration=1/' "$t"
elif grep -Eq '^bwlimit:' "$t"; then
  sed -i -E '/^bwlimit:/ s/[[:space:]]*$/,migration=1/' "$t"
else
  printf 'bwlimit: migration=1\n' >>"$t"
fi
cat "$t" >"$f"
rm -f "$t"
pose "$f"
journal "datacenter.cfg : bwlimit migration=1 (Kio/s)"
EOF
      ;;
  esac
  ((rc == 0)) || { _e38_defaire "$n"; return "$rc"; }
  if ! m09_attendre 30 _e38_effet "$n"; then
    _e38_defaire "$n"
    return 10
  fi
}

_e38_defaire() {
  case "$1" in
    1)
      # Variante sans effet (essai de la suivante) : on retire le disque local ; à l'annulation, il
      # part de toute façon avec la VM de test.
      m09_ssh hv01 "qm config 194 2>/dev/null | grep -q '^scsi1: local-lvm' && qm set 194 --delete scsi1 >/dev/null && qm set 194 --delete unused0 >/dev/null" >/dev/null 2>&1 || true
      ;;
    2)
      m09_exec hv01 >/dev/null <<'EOF' || true
[ -f "$WB_DIR/$WB_EX.iso" ] || exit 0
d="$(cat "$WB_DIR/$WB_EX.iso")"
qm set 194 --ide2 none,media=cdrom >/dev/null 2>&1 || true
rm -f "$d" "$WB_DIR/$WB_EX.iso"
journal "annulation : ISO de test retirée"
EOF
      ;;
    3)
      m09_exec hv02 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv02 (table nftables)"
table_retirer
EOF
      ;;
    4)
      m09_exec hv01 >/dev/null <<'EOF' || wb_avert "annulation incomplète (datacenter.cfg)"
[ -f "$WB_DIR/$WB_EX.$(_cle /etc/pve/datacenter.cfg).pose" ] || exit 0
rendre /etc/pve/datacenter.cfg >/dev/null
EOF
      ;;
  esac
}

_e38_injecter() {
  _e38_precondition || return 1
  m09_essayer E38 4 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }
panne_E38_v4() { _e38_injecter 4; }

verifier_E38() {
  _e38_effet "${WB_VAR:-1}"
}

annuler_E38() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e38_defaire "$WB_VAR" ;;
    *) _e38_defaire 4; _e38_defaire 3; _e38_defaire 2 ;;
  esac
  m09_vm_detruire E38 194
}

resume_E38() {
  echo "La migration à chaud de pan-mig (194) de hv01 vers hv02 échoue ou ne se termine jamais."
}

symptome_E38() {
  wb_symptome "Ticket INC-3644 — De : Julien Petit" \
    "Je dois libérer hv01 pour la maintenance de cet après-midi. La migration à chaud de ma VM" \
    "pan-mig (VMID 194, hv01) vers hv02 ne passe pas : selon l'essai, elle est refusée tout de" \
    "suite ou elle démarre et n'avance plus. Les autres VMs, je ne les ai pas encore essayées." \
    "Hors de question de l'arrêter : elle doit être migrée à chaud." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 09 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E38 4 "$@"; }
fi
