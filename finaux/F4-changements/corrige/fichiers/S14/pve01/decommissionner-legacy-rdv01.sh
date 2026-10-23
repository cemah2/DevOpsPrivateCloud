#!/usr/bin/env bash
# decommissionner-legacy-rdv01.sh — décommissionnement de legacy-rdv01 (VM 3401), F4-S14, CHG-3414.
# Solution de référence de RB-347, partie « hyperviseur ». Root sur pve01. Étapes :
#   sauvegarde  sauvegarde finale (VM arrêtée) vers pbs-par2, PROTÉGÉE contre l'élagage
#   essai       restauration d'essai en 3499 (réseau coupé), contrôle par l'agent, puis effacement de 3499
#   effacer     effacement des disques de 3401 (une passe aléatoire + une passe de zéros) et preuve
#   detruire    suppression de la VM 3401 (APRÈS « tofu state rm » dans envs/f4-infoger, voir RB-347)
#   export      effacement de l'export d'InfoGér de legacy-rdv01 (hdd-bulk:import/infoger-export/)
#
#   decommissionner-legacy-rdv01.sh <étape> [--conserver-jusqu-au AAAA-MM-JJ]
#
# Preuves : /root/decommissionnement-legacy-rdv01/ (journal horodaté de chaque commande et de son
# résultat, empreintes) : à joindre à CHG-3414 (sans aucune donnée de santé).
# ⚠️ « effacer », « detruire » et « export » sont IRRÉVERSIBLES : chacun vérifie d'abord qu'une
# sauvegarde finale protégée existe et que la restauration d'essai a réussi.
set -euo pipefail

VMID=3401
ESSAI=3499
PBS=pbs-par2
NOEUD="$(hostname -s)"
PREUVES=/root/decommissionnement-legacy-rdv01
mkdir -p "$PREUVES" && chmod 700 "$PREUVES"
JOURNAL="$PREUVES/journal.txt"
trace() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$JOURNAL"; }
mourir() { trace "ARRÊT : $*"; exit 1; }
confirmer() {
  printf '⚠️  %s\n   Tape « %s » pour continuer : ' "$1" "$2"
  local r; read -r r; [[ "$r" == "$2" ]] || mourir "non confirmé"
}

etape="${1:-}"; shift || true
jusqu=""
if [[ "${1:-}" == --conserver-jusqu-au ]]; then jusqu="${2:-}"; fi

sauvegarde_finale() { cat "$PREUVES/sauvegarde-finale" 2>/dev/null || true; }
essai_reussi() { [[ -f "$PREUVES/essai-restauration-ok" ]]; }

case "$etape" in
  sauvegarde)
    [[ "$jusqu" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || mourir "--conserver-jusqu-au AAAA-MM-JJ obligatoire (politique validée par Sophie Laurent)"
    trace "arrêt de $VMID et sauvegarde finale vers $PBS (mode stop : disque cohérent)"
    qm shutdown "$VMID" --timeout 180 || qm stop "$VMID"
    # --protected 1 : la sauvegarde échappe à l'élagage du travail f4-infoger (keep-daily=7…).
    vzdump "$VMID" --storage "$PBS" --mode stop --protected 1 \
      --notes-template "SAUVEGARDE FINALE legacy-rdv01 (CHG-3414) - protegee, conserver jusqu'au $jusqu" 2>&1 | tee -a "$JOURNAL"
    volid="$(pvesm list "$PBS" --vmid "$VMID" | awk 'NR > 1 {print $1}' | sort | tail -n 1)"
    [[ -n "$volid" ]] || mourir "sauvegarde introuvable dans $PBS"
    pvesh get "/nodes/$NOEUD/storage/$PBS/content" --vmid "$VMID" --output-format json \
      | VOLID="$volid" perl -MJSON::PP -0777 -ne 'exit((grep { $_->{volid} eq $ENV{VOLID} && $_->{protected} } @{decode_json($_)}) ? 0 : 1)' \
      || mourir "la sauvegarde $volid n'est pas protégée"
    printf '%s\n' "$volid" > "$PREUVES/sauvegarde-finale"
    trace "sauvegarde finale $volid protégée (conservation jusqu'au $jusqu)"
    ;;
  essai)
    volid="$(sauvegarde_finale)"; [[ -n "$volid" ]] || mourir "pas de sauvegarde finale"
    qm status "$ESSAI" >/dev/null 2>&1 && mourir "le VMID $ESSAI existe déjà"
    trace "restauration d'essai de $volid en $ESSAI (réseau coupé)"
    qmrestore "$volid" "$ESSAI" --storage local-nvme --unique 1 2>&1 | tail -n 3 | tee -a "$JOURNAL"
    qm set "$ESSAI" --name legacy-rdv01-essai --onboot 0 --net0 "$(qm config "$ESSAI" | sed -nE 's/^net0: (.*)$/\1/p'),link_down=1" >/dev/null
    qm start "$ESSAI"
    for _ in $(seq 1 36); do qm guest cmd "$ESSAI" ping >/dev/null 2>&1 && break; sleep 5; done
    sortie="$(qm guest exec "$ESSAI" --timeout 60 -- mariadb -N -B -e 'SELECT COUNT(*) FROM legacy_rdv.rendez_vous')"
    trace "restauration d'essai : $(printf '%s' "$sortie" | tr -d '\n' | sed 's/  */ /g')"
    printf '%s' "$sortie" | grep -Eq '"out-data"[[:space:]]*:[[:space:]]*"[0-9]+' || mourir "la base restaurée ne répond pas"
    touch "$PREUVES/essai-restauration-ok"
    qm stop "$ESSAI"
    for d in $(qm config "$ESSAI" | sed -nE 's/^(scsi[0-9]+|efidisk0): ([^,]+).*/\2/p'); do
      dev="$(pvesm path "$d")"
      trace "effacement du disque d'essai $d ($dev)"
      shred -n 1 -z "$dev"
    done
    qm destroy "$ESSAI" --purge 1 --destroy-unreferenced-disks 1
    trace "VM d'essai $ESSAI effacée et supprimée"
    ;;
  effacer)
    if [[ -z "$(sauvegarde_finale)" ]] || ! essai_reussi; then
      mourir "sauvegarde finale ou restauration d'essai manquante"
    fi
    qm status "$VMID" | grep -q stopped || mourir "$VMID doit être arrêtée"
    confirmer "effacement DÉFINITIF des disques de legacy-rdv01 ($VMID)" "effacer $VMID"
    for d in $(qm config "$VMID" | sed -nE 's/^(scsi[0-9]+|virtio[0-9]+|efidisk0|unused[0-9]+): ([^,]+).*/\2/p'); do
      dev="$(pvesm path "$d")"
      trace "effacement de $d ($dev) : une passe aléatoire, une passe de zéros"
      shred -n 1 -z -v "$dev" 2>&1 | tail -n 1 | tee -a "$JOURNAL"
      taille=$(blockdev --getsize64 "$dev")
      # Preuve : 64 Mio lus en début, au milieu et en fin de volume sont entièrement nuls.
      for pos in 0 $((taille / 2 / 1048576)) $((taille / 1048576 - 64)); do
        if cmp -s -n $((64 * 1048576)) <(dd if="$dev" bs=1M skip="$pos" count=64 status=none) /dev/zero; then
          trace "  $d : 64 Mio nuls à partir de $pos Mio"
        else
          mourir "$d : données non nulles à partir de $pos Mio"
        fi
      done
    done
    touch "$PREUVES/disques-effaces"
    sha256sum "$JOURNAL" | tee "$PREUVES/journal.sha256"
    ;;
  detruire)
    [[ -f "$PREUVES/disques-effaces" ]] || mourir "disques non effacés"
    confirmer "suppression de la VM $VMID (déjà retirée de l'état OpenTofu par « tofu state rm »)" "detruire $VMID"
    qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1
    trace "VM $VMID supprimée (configuration, disques, travaux de sauvegarde et de réplication)"
    ;;
  export)
    essai_reussi || mourir "restauration d'essai manquante"
    racine="$(pvesh get /storage/hdd-bulk --output-format json | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{path} // ""')"
    d="$racine/import/infoger-export/legacy-rdv01"
    [[ -d "$d" ]] || mourir "export de legacy-rdv01 introuvable ($d)"
    confirmer "effacement de l'export d'InfoGér de legacy-rdv01 ($d)" "effacer export"
    sha256sum "$d"/* | tee -a "$JOURNAL"
    shred -n 1 -z -u -v "$d"/* 2>&1 | tail -n 3 | tee -a "$JOURNAL"
    rmdir "$d"
    trace "export de legacy-rdv01 effacé (ftp-part01 et stats01 conservés jusqu'à leur décommissionnement)"
    ;;
  *) echo "usage : $0 sauvegarde --conserver-jusqu-au AAAA-MM-JJ | essai | effacer | detruire | export" >&2; exit 2 ;;
esac
