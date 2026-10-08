# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E29.sh — M09-E29 « Reconstruire un nœud, restaurer le cluster »
# Lecture seule : unités et secrets de sauvegarde des nœuds, arborescence du datastore sur pbs01
# (find, sans rien modifier), journal des tâches de pve01, état du cluster et de Ceph, GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E29 — Reconstruire un nœud, restaurer le cluster"
require_cmd jq ssh
_m09p_charger

title "Sauvegarde de configuration des nœuds"
for _m09_e29_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e29_n : minuterie wb-backup-socle active, dernier passage réussi" "$_m09_e29_n" \
    'systemctl is-active --quiet wb-backup-socle.timer && [ "$(systemctl show -p Result --value wb-backup-socle.service)" = success ] && [ "$(systemctl show -p ExecMainStartTimestampMonotonic --value wb-backup-socle.service)" != 0 ]'
  check_ssh "$_m09_e29_n : élément pve configuré, secrets PBS en root:root 600" "$_m09_e29_n" \
    'grep -Eq "^WB_ELEMENTS=\"?([a-z]+ )*pve" /etc/wb-backup/socle.conf && for f in /etc/wb-backup/pbs-$(hostname -s).env /etc/wb-backup/pbs-$(hostname -s).key; do [ "$(stat -c %U:%a "$f")" = root:600 ] || exit 1; done'
done

# _m09_e29_pbs NŒUD — sur pbs01 : un instantané host/<nœud> de moins de 48 h dans par1/hv ; si son
# manifeste est lisible en clair, il doit déclarer un chiffrement.
_m09_e29_pbs() {
  local chemin
  chemin="$(remote "$WB_PBS_HOST" "awk '/^datastore: *ds-lab/ {f=1; next} /^[a-z]+:/ {f=0} f && \$1 == \"path\" {print \$2; exit}' /etc/proxmox-backup/datastore.cfg" 2>/dev/null)" || return 1
  [[ -n "$chemin" ]] || return 1
  remote "$WB_PBS_HOST" "d=\$(find '$chemin/ns/par1/ns/hv/host/$1' -mindepth 1 -maxdepth 1 -type d -mmin -2880 2>/dev/null | sort | tail -n 1); [ -n \"\$d\" ] || exit 1; m=\"\$d/index.json.blob\"; [ -s \"\$m\" ] || exit 1; if grep -aq '\"files\"' \"\$m\"; then grep -aq 'encrypt' \"\$m\"; fi"
}
for _m09_e29_n in "${_M09P_NOEUDS[@]}"; do
  check_cmd "pbs01 : instantané host/$_m09_e29_n de moins de 48 h dans par1/hv (chiffré)" _m09_e29_pbs "$_m09_e29_n"
done

title "Reconstruction de hv03"
check_cmd "VM 2093 recréée (au moins deux créations dans le journal de pve01)" _m09p_creations_min 2093 2
check_cmd "cluster quorate, trois nœuds en ligne" _m09p_quorate_3
check_ssh "aucun nœud fantôme (/etc/pve/nodes = hv01, hv02, hv03)" "hv01" \
  '[ "$(ls /etc/pve/nodes | sort | tr "\n" " ")" = "hv01 hv02 hv03 " ]'
check_cmd "Ceph en HEALTH_OK" _m09p_ceph_ok
check_cmd "Ceph : 3 MON en quorum, 6 OSD existants, 6 up et in" _m09p_ceph_jq status \
  '(.quorum_names | length) == 3 and .osdmap.num_osds == 6 and .osdmap.num_up_osds == 6 and .osdmap.num_in_osds == 6'
check_cmd "Ceph : hv03 porte un MON" _m09p_ceph_jq status '.quorum_names | index("hv03") != null'
check_ssh "Ceph : hv03 porte deux OSD" "hv01" '[ "$(ceph osd ls-tree hv03 | wc -l)" -eq 2 ]'

title "Restaurations et réplication"
check_cmd "VM 127 en marche sur hv03" _m09p_vm_cluster 127 '.node == "hv03" and .status == "running"'
_m09_e29_repli() {
  local n j ok=0 t
  t="$(date +%s)"
  for n in "${_M09P_NOEUDS[@]}"; do
    j="$(_m09p_hv "$n" "pvesh get /nodes/$n/replication --output-format json" 2>/dev/null)" || return 1
    jq -e 'all(.[]; (.fail_count // 0) == 0)' >/dev/null <<<"$j" || return 1
    if jq -e --argjson t "$t" 'any(.[]; .target == "hv03" and ($t - (.last_sync // 0)) < 3600)' >/dev/null <<<"$j"; then ok=1; fi
  done
  ((ok == 1))
}
check_cmd "réplication : aucun échec, une tâche vers hv03 synchronisée depuis moins d'une heure" _m09_e29_repli

title "Documentation"
check_cmd "RB-091 sur main (docs/virtualisation/runbooks/)" _m09p_doc runbooks RB-091
check_cmd "compte rendu de reprise sur main (docs/virtualisation/tests/reprise-hv-par1.md)" _m09p_doc tests reprise-hv-par1
