# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M09-E37 « Panne : une VM HA reste en erreur »
#
# Invités de test créés par la panne (VMID 191-193, « pan-ha1..3 », sans système, étiquette pannes-m09).
# Variantes :
#   1. stockage local : pan-ha1 (191) créée sur hv02 avec son disque sur local-lvm, ressource HA en
#      « stopped » ; son fichier de configuration est ensuite DÉPLACÉ à la main vers hv01 (« pour la
#      relancer ailleurs ») et la ressource passe en « started » → démarrage impossible sur hv01
#      (volume absent), relocalisation impossible (disque local introuvable) → error ;
#   2. règle impossible : pan-ha1..3 (191-193) sur ceph-vm, une par nœud, règle d'affinité de
#      ressources NÉGATIVE « separer-pan-ha » sur les trois ; puis hv03 passe en maintenance
#      (RB-090) → la ressource de hv03 n'a plus de nœud autorisé → error ;
#   3. max_restart atteint : pan-ha1 (191) sur ceph-vm avec un second disque dont l'image RBD est
#      supprimée par un « nettoyage des images orphelines » (pvesm free) ; ressource HA « started »
#      → échec de démarrage partout, max_restart puis max_relocate épuisés → error.
# Tout est détruit à l'annulation (ressources HA, règle, VMs ; maintenance levée si posée ici).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E37_REGLE=separer-pan-ha

_e37_precondition() {
  m09_cluster_sain || return 1
  local id
  for id in 191 192 193; do
    m09_vmid_libre "$id" || { wb_avert "le VMID $id (réservé aux pannes du palier 4) est déjà pris dans le cluster"; return 1; }
  done
  if m09_ha_desarmee; then
    wb_avert "la pile HA est désarmée : réarme-la (ha-manager crm-command arm-ha) avant cette panne"
    return 1
  fi
  m09_stockage_actif hv01 ceph-vm || { wb_avert "stockage ceph-vm inactif sur hv01 (M09-E10)"; return 1; }
  m09_stockage_actif hv02 local-lvm || { wb_avert "stockage local-lvm inactif sur hv02"; return 1; }
  if m09_ha_status | grep -Eq "^lrm [a-z0-9-]+ \\(maintenance"; then
    wb_avert "un nœud est déjà en maintenance HA : lève-la avant la panne"
    return 1
  fi
}

# _e37_erreur — une des ressources vm:191-193 est en état error.
_e37_erreur() {
  m09_ha_status | grep -Eq '^service vm:19[123] \([^)]*error\)'
}

_mE37_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m09_vm_creer E37 191 pan-ha1 hv02 local-lvm:1 || rc=1
      ((rc == 0)) && { m09_ssh hv02 "ha-manager add vm:191 --state stopped --max_restart 1 --max_relocate 1 --comment 'VM de test de Julien'" >/dev/null 2>&1 || rc=1; }
      ((rc == 0)) && sleep 15
      ((rc == 0)) && { m09_exec hv02 >/dev/null <<'EOF' || rc=$?; }
[ -f /etc/pve/nodes/hv02/qemu-server/191.conf ] || exit 1
mv /etc/pve/nodes/hv02/qemu-server/191.conf /etc/pve/nodes/hv01/qemu-server/191.conf
journal "191.conf déplacé à la main de hv02 vers hv01 (disque sur local-lvm de hv02)"
EOF
      ((rc == 0)) && { sleep 5; m09_ssh hv01 "ha-manager set vm:191 --state started" >/dev/null 2>&1 || rc=1; }
      ;;
    2)
      local id h i=0
      for h in hv01 hv02 hv03; do
        id=$((191 + i)); i=$((i + 1))
        m09_vm_creer E37 "$id" "pan-ha$i" "$h" ceph-vm:1 || { rc=1; break; }
        m09_ssh "$h" "ha-manager add vm:$id --state started --max_restart 1 --max_relocate 1" >/dev/null 2>&1 || { rc=1; break; }
      done
      if ((rc == 0)); then
        if m09_ssh hv01 "ha-manager rules add resource-affinity $_E37_REGLE --affinity negative --resources vm:191,vm:192,vm:193 --comment 'Jamais deux frontaux sur le même nœud'" >/dev/null 2>&1; then
          m09_ecrire E37 regle 1
        else
          rc=1
        fi
      fi
      if ((rc == 0)); then
        # Les trois doivent tourner, une par nœud, avant la maintenance.
        local t
        for ((t = 0; t < 120; t += 5)); do
          [[ "$(m09_ha_etat 191)$(m09_ha_etat 192)$(m09_ha_etat 193)" == startedstartedstarted ]] && break
          sleep 5
        done
        if m09_ssh hv01 "ha-manager crm-command node-maintenance enable hv03" >/dev/null 2>&1; then
          m09_ecrire E37 maintenance hv03
          m09_journal E37 "hv03 mis en maintenance HA (règle négative sur 3 ressources, 3 nœuds)"
        else
          rc=1
        fi
      fi
      ;;
    3)
      m09_vm_creer E37 191 pan-ha1 hv01 ceph-vm:1 || rc=1
      ((rc == 0)) && { m09_ssh hv01 "qm set 191 --scsi1 ceph-vm:1" >/dev/null 2>&1 || rc=1; }
      ((rc == 0)) && { m09_exec hv01 >/dev/null <<'EOF' || rc=$?; }
v="$(sed -nE 's/^scsi1: ([^,]+).*/\1/p' /etc/pve/qemu-server/191.conf)"
[ -n "$v" ] || exit 1
pvesm free "$v" >/dev/null 2>&1 || exit 1
journal "image $v supprimée par pvesm free (référence laissée dans 191.conf)"
EOF
      ((rc == 0)) && { m09_ssh hv01 "ha-manager add vm:191 --state started --max_restart 1 --max_relocate 1 --comment 'VM de test de Julien'" >/dev/null 2>&1 || rc=1; }
      ;;
  esac
  ((rc == 0)) || { _e37_defaire; return 1; }
  # Démarrages, redémarrages et relocalisations : plusieurs minutes avant l'état error.
  if ! m09_attendre 300 _e37_erreur; then
    _e37_defaire
    return 10
  fi
}

_e37_defaire() {
  local n
  n="$(m09_un_quorate || echo hv01)"
  if [[ -n "$(m09_lire E37 maintenance)" ]]; then
    m09_ssh "$n" "ha-manager crm-command node-maintenance disable hv03" >/dev/null 2>&1 || true
    m09_effacer E37 maintenance
    m09_journal E37 "annulation : maintenance HA de hv03 levée (si encore active)"
  fi
  if [[ -n "$(m09_lire E37 regle)" ]]; then
    m09_ssh "$n" "ha-manager rules remove $_E37_REGLE 2>/dev/null || ha-manager rules delete $_E37_REGLE 2>/dev/null" >/dev/null 2>&1 || true
    m09_effacer E37 regle
    m09_journal E37 "annulation : règle $_E37_REGLE retirée (si encore présente)"
  fi
  local id
  for id in 191 192 193; do
    m09_vm_detruire E37 "$id"
  done
}

_e37_injecter() {
  _e37_precondition || return 1
  m09_essayer E37 3 "$1"
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }

verifier_E37() {
  _e37_erreur
}

annuler_E37() {
  _e37_defaire
}

resume_E37() {
  echo "Une VM de test sous HA (pan-ha*) est en état « error » et ne redémarre plus d'elle-même."
}

symptome_E37() {
  wb_symptome "Ticket INC-3643 — De : Julien Petit" \
    "Ma VM de recette sous HA (pan-ha*, VMID 191 à 193) est marquée « error » dans l'écran HA" \
    "et ne redémarre plus. J'ai cliqué sur « Démarrer » : la demande est refusée ou rien ne se passe." \
    "Elle doit tourner avant midi pour les tests de charge. Ne la recrée pas : je veux comprendre" \
    "pourquoi la HA a abandonné, et que ça ne se reproduise pas sur les vraies VMs." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 09 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E37 3 "$@"; }
fi
