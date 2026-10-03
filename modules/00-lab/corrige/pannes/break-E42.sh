# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M00-E42 « Panne : la sauvegarde nocturne a échoué »
#
# Variantes :
#   1. empreinte (fingerprint) du stockage pbs-par2 altérée sur pve01 (dernier octet) ;
#   2. ACL de wb-backup@pbs (utilisateur et jeton) retirées sur pbs01 ;
#   3. datastore ds-lab passé en mode maintenance « read-only » sur pbs01 ;
#   4. namespace du stockage pbs-par2 changé en « par1-prod » (inexistant) sur pve01.
# Une sauvegarde de dns01 est ensuite lancée en arrière-plan pour produire la tâche en échec.
# Sauvegardes : /var/lib/workbook/E42.* sur pve01 / pbs01.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

_E42_lancer_sauvegarde() {
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_DNS01" >/dev/null <<'EOF' || true
setsid nohup vzdump "$VMID" --storage pbs-par2 --mode snapshot >/dev/null 2>&1 < /dev/null &
exit 0
EOF
}

panne_E42_v1() {
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || return 1
fp="$(awk '/^pbs: pbs-par2$/{f=1;next} /^[a-z]+: /{f=0} f && $1=="fingerprint"{print $2}' /etc/pve/storage.cfg)"
if [ -n "$fp" ]; then
  fin="${fp##*:}"
  if [ "$fin" = "00" ]; then nouveau="ff"; else nouveau="00"; fi
  faux="${fp%:*}:$nouveau"
else
  fp="AUCUNE"
  faux="$(openssl rand -hex 32 | sed 's/../&:/g; s/:$//')"
fi
[ -f "$WB_DIR/E42.fingerprint" ] || printf '%s\n' "$fp" > "$WB_DIR/E42.fingerprint"
pvesm set pbs-par2 --fingerprint "$faux" || exit 1
journal "fingerprint de pbs-par2 : $fp → $faux"
EOF
  _E42_lancer_sauvegarde
}

panne_E42_v2() {
  local rc=0
  wb_exec "$WB_PBS_HOST" >/dev/null <<'EOF' || rc=$?
acl=/etc/proxmox-backup/acl.cfg
# Format : acl:<propagate>:<chemin>:<ugid1,ugid2…>:<rôle1,rôle2…>
lignes="$(grep -E '^acl:[01]:[^:]*:[^:]*wb-backup@pbs' "$acl" 2>/dev/null || true)"
[ -n "$lignes" ] || exit 3
: > "$WB_DIR/E42.acl-retirees"
printf '%s\n' "$lignes" | while IFS=: read -r _ prop chemin ugids roles; do
  for u in $(printf '%s' "$ugids" | tr ',' ' '); do
    case "$u" in *wb-backup@pbs*) ;; *) continue ;; esac
    for r in $(printf '%s' "$roles" | tr ',' ' '); do
      printf '%s %s %s %s\n' "$prop" "$chemin" "$u" "$r" >> "$WB_DIR/E42.acl-retirees"
      proxmox-backup-manager acl update "$chemin" "$r" --auth-id "$u" --delete true
    done
  done
done
journal "ACL retirées : $(tr '\n' ';' < "$WB_DIR/E42.acl-retirees")"
EOF
  if ((rc == 3)); then
    # Aucune ACL trouvée pour wb-backup@pbs : on bascule sur la variante 3.
    WB_VAR=3
    panne_E42_v3
    return
  fi
  ((rc == 0)) || return "$rc"
  _E42_lancer_sauvegarde
}

panne_E42_v3() {
  wb_exec "$WB_PBS_HOST" >/dev/null <<'EOF' || return 1
proxmox-backup-manager datastore update ds-lab --maintenance-mode type=read-only || exit 1
: > "$WB_DIR/E42.maintenance"
journal "datastore ds-lab passé en maintenance read-only"
EOF
  _E42_lancer_sauvegarde
}

panne_E42_v4() {
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || return 1
ns="$(awk '/^pbs: pbs-par2$/{f=1;next} /^[a-z]+: /{f=0} f && $1=="namespace"{print $2}' /etc/pve/storage.cfg)"
[ -f "$WB_DIR/E42.namespace" ] || printf '%s\n' "${ns:-AUCUN}" > "$WB_DIR/E42.namespace"
pvesm set pbs-par2 --namespace par1-prod || exit 1
journal "namespace de pbs-par2 : ${ns:-aucun} → par1-prod"
EOF
  _E42_lancer_sauvegarde
}

annuler_E42() {
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/E42.fingerprint" ]; then
  fp="$(cat "$WB_DIR/E42.fingerprint")"
  if [ "$fp" = "AUCUNE" ]; then pvesm set pbs-par2 --delete fingerprint; else pvesm set pbs-par2 --fingerprint "$fp"; fi
  rm -f "$WB_DIR/E42.fingerprint"
fi
if [ -f "$WB_DIR/E42.namespace" ]; then
  ns="$(cat "$WB_DIR/E42.namespace")"
  if [ "$ns" = "AUCUN" ]; then pvesm set pbs-par2 --delete namespace; else pvesm set pbs-par2 --namespace "$ns"; fi
  rm -f "$WB_DIR/E42.namespace"
fi
journal "annulation : configuration du stockage pbs-par2 rétablie"
EOF
  wb_exec "$WB_PBS_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pbs01"
if [ -f "$WB_DIR/E42.acl-retirees" ]; then
  while read -r prop chemin u r; do
    if [ "$prop" = "1" ]; then p=true; else p=false; fi
    proxmox-backup-manager acl update "$chemin" "$r" --auth-id "$u" --propagate "$p" || true
  done < "$WB_DIR/E42.acl-retirees"
  rm -f "$WB_DIR/E42.acl-retirees"
fi
if [ -f "$WB_DIR/E42.maintenance" ]; then
  proxmox-backup-manager datastore update ds-lab --delete maintenance-mode && rm -f "$WB_DIR/E42.maintenance"
fi
journal "annulation : ACL et mode du datastore rétablis"
EOF
}

resume_E42() {
  echo "Le rapport de la sauvegarde nocturne vers pbs-par2 est en erreur pour toutes les VMs."
}

symptome_E42() {
  wb_symptome "Ticket INC-2612 — De : Nadia Roussel" \
    "La notification de cette nuit indique que le job de sauvegarde vers pbs-par2" \
    "s'est terminé en erreur (« backup failed ») pour les VMs du socle." \
    "Une relance manuelle de la sauvegarde de dns01 échoue aussi (tâche en erreur dans pve01)." \
    "Pas de sauvegarde valide de la nuit : à corriger avant ce soir, et relance une sauvegarde." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 00 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E42 4 "$@"; }
fi
