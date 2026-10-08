# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M09-E40 « Panne : la réplication est en échec »
#
# Invité de test : pan-rep (VMID 196) sur hv01, disque de 1 Gio sur zfs-local, job de réplication
# 196-0 vers hv02 (toutes les 15 min), première synchronisation complète faite avant la panne.
# Variantes :
#   1. pool ZFS de hv02 plein : un jeu de données « export-infoger » avec une réservation qui prend
#      presque toute la place, et 300 Mio écrits dans le disque de 196 sur hv01 → l'envoi incrémental
#      ne tient plus (« out of space ») ;
#   2. instantanés divergents : le dernier instantané de réplication (__replicate_196-0_…__) détruit
#      sur hv02 (« nettoyage des vieux snapshots ») → plus de base commune pour l'incrémental ;
#   3. clés SSH : /root/.ssh/authorized_keys de hv02 remplacé par un fichier « géré par Ansible » qui
#      ne contient plus les clés des nœuds (le lien vers /etc/pve/priv/authorized_keys, s'il existait,
#      est perdu) → hv01 ne peut plus ouvrir de session SSH vers hv02 ; l'accès de adm01 est conservé.
# Sauvegardes : /var/lib/workbook/M09-E40.* sur hv02 ; état local ~/.local/state/workbook/M09-E40/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E40_JOB=196-0

# _e40_statut — JSON du job de réplication 196-0 vu de hv01 (fail_count, error, last_sync…).
_e40_statut() {
  m09_json hv01 "/nodes/hv01/replication/$_E40_JOB/status"
}

_e40_en_echec() {
  local j
  j="$(_e40_statut)" || return 1
  jq -e '((.fail_count // 0) > 0) or ((.error // "") != "")' <<<"$j" >/dev/null 2>&1
}

_e40_synchro_ok() {
  local j
  j="$(_e40_statut)" || return 1
  jq -e '((.last_sync // 0) > 0) and ((.fail_count // 0) == 0)' <<<"$j" >/dev/null 2>&1
}

# _e40_lancer — demande une synchronisation immédiate (le planificateur la prend dans la minute).
_e40_lancer() {
  m09_ssh hv01 "pvesr schedule-now $_E40_JOB" >/dev/null 2>&1 || true
}

_e40_precondition() {
  m09_cluster_sain || return 1
  m09_vmid_libre 196 || { wb_avert "le VMID 196 (réservé aux pannes du palier 4) est déjà pris"; return 1; }
  local h
  for h in hv01 hv02; do
    m09_stockage_actif "$h" zfs-local || { wb_avert "stockage zfs-local inactif sur $h (M09-E06/E14)"; return 1; }
  done
  m09_vm_creer E40 196 pan-rep hv01 zfs-local:1 || return 1
  m09_ssh hv01 "pvesr create-local-job $_E40_JOB hv02 --schedule '*/15' --comment 'Recette réplication (Julien)'" >/dev/null 2>&1 \
    || { wb_avert "création du job de réplication $_E40_JOB impossible"; return 1; }
  m09_ecrire E40 job 1
  _e40_lancer
  m09_attendre 180 _e40_synchro_ok || { wb_avert "la première réplication de 196 vers hv02 n'aboutit pas (lab sain ?)"; return 1; }
}

_mE40_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m09_exec hv02 >/dev/null <<'EOF' || rc=$?
p="$(stockage_section zfs-local pool)"
[ -n "$p" ] || exit 10
d="${p%%/*}/export-infoger"
zfs list -H "$d" >/dev/null 2>&1 && exit 10
dispo="$(zfs get -Hp -o value available "${p%%/*}")"
res=$((dispo - 104857600))
[ "$res" -gt 0 ] || exit 10
zfs create -o refreservation="$res" "$d" || exit 1
printf '%s\n' "$d" >"$WB_DIR/$WB_EX.jeu"
journal "jeu de données $d créé avec refreservation=$res (pool presque plein)"
EOF
      if ((rc == 0)); then
        # Données nouvelles côté source : l'incrémental suivant pèse ~300 Mio.
        m09_exec hv01 >/dev/null <<'EOF' || rc=$?
p="$(stockage_section zfs-local pool)"
z="/dev/zvol/$p/vm-196-disk-0"
[ -e "$z" ] || exit 1
dd if=/dev/urandom of="$z" bs=1M count=300 oflag=direct status=none
journal "300 Mio écrits dans $z"
EOF
      fi
      ;;
    2)
      m09_exec hv02 >/dev/null <<'EOF' || rc=$?
p="$(stockage_section zfs-local pool)"
s="$(zfs list -H -t snapshot -o name -s creation "$p/vm-196-disk-0" 2>/dev/null | grep '@__replicate_196-0_' | tail -n 1)"
[ -n "$s" ] || exit 10
zfs destroy "$s" || exit 1
journal "instantané $s détruit sur hv02"
EOF
      ;;
    3)
      m09_exec hv02 >/dev/null <<'EOF' || rc=$?
f=/root/.ssh/authorized_keys
[ -e "$f" ] || exit 10
t="$(mktemp)"
cat "$f" | grep -Ev 'root@hv0[1-3]([[:space:]]|$)' >"$t" || true
# Garde-fou : il doit rester au moins une clé (celle de adm01), et avoir retiré quelque chose.
[ -s "$t" ] || { rm -f "$t"; exit 10; }
[ "$(wc -l <"$t")" -lt "$(wc -l <"$f")" ] || { rm -f "$t"; exit 10; }
garder "$f"
{ echo "# Fichier géré par Ansible (durcissement InfoGér) — ne pas modifier"; cat "$t"; } >"$f.neuf"
rm -f "$t" "$f"
mv "$f.neuf" "$f"
chmod 600 "$f"
pose "$f"
journal "authorized_keys de root remplacé par un fichier sans les clés des nœuds"
EOF
      ;;
  esac
  ((rc == 0)) || { _e40_defaire "$n"; return "$rc"; }
  _e40_lancer
  if ! m09_attendre 180 _e40_en_echec; then
    _e40_defaire "$n"
    return 10
  fi
}

_e40_defaire() {
  case "$1" in
    1)
      m09_exec hv02 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv02 (jeu de données ZFS)"
[ -f "$WB_DIR/$WB_EX.jeu" ] || exit 0
d="$(cat "$WB_DIR/$WB_EX.jeu")"
if zfs list -H "$d" >/dev/null 2>&1; then
  zfs destroy "$d" && journal "annulation : $d détruit"
else
  journal "annulation : $d déjà supprimé (réparation)"
fi
rm -f "$WB_DIR/$WB_EX.jeu"
EOF
      ;;
    2) : ;;  # le volume répliqué disparaît avec le job et la VM de test
    3)
      m09_exec hv02 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur hv02 (authorized_keys)"
[ -f "$WB_DIR/$WB_EX.$(_cle /root/.ssh/authorized_keys).pose" ] || exit 0
rendre /root/.ssh/authorized_keys >/dev/null
EOF
      ;;
  esac
}

# _e40_nettoyer — job de réplication et VM de test (après la remise en état des variantes).
_e40_nettoyer() {
  if [[ -n "$(m09_lire E40 job)" ]]; then
    # Suppression normale (retire aussi le volume répliqué sur hv02), puis forcée si SSH est encore cassé.
    m09_ssh hv01 "pvesr delete $_E40_JOB" >/dev/null 2>&1 || true
    sleep 20
    if m09_ssh hv01 "pvesr list" 2>/dev/null | grep -q "^$_E40_JOB"; then
      m09_ssh hv01 "pvesr delete $_E40_JOB --force 1" >/dev/null 2>&1 || true
    fi
    m09_effacer E40 job
  fi
  m09_vm_detruire E40 196
}

_e40_injecter() {
  _e40_precondition || return 1
  m09_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() {
  _e40_en_echec
}

annuler_E40() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 3; _e40_defaire 1 ;;
  esac
  _e40_nettoyer
}

resume_E40() {
  echo "La réplication ZFS 196-0 (pan-rep, hv01 → hv02) est en échec depuis la nuit."
}

symptome_E40() {
  wb_symptome "Ticket INC-3646 — De : Julien Petit" \
    "La réplication de ma VM de recette pan-rep (196, hv01 → hv02, job 196-0) est en échec :" \
    "l'onglet « Réplication » affiche une erreur et le compteur d'échecs monte. On m'a vendu un" \
    "RPO de 15 minutes pour cette VM. Je veux la réplication rétablie sans repartir de zéro si" \
    "c'est possible, et savoir si d'autres jobs du cluster sont touchés." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 09 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E40 3 "$@"; }
fi
