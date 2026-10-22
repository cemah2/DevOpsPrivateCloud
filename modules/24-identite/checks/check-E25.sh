# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E25.sh — M24-E25 : Sauvegarder et restaurer l'identité
# À lancer depuis adm01. Lecture seule : minuteries, trace du dernier succès et droits des secrets sur
# idp01 et ipa01 (sudo -n), stockage et tâche de sauvegarde Proxmox (pvesh, pvesm sur pve01), RB-243
# sur main, absence d'idp-resto.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E25 — Sauvegarder et restaurer l'identité"
require_cmd jq curl

# _m24p_e25_age HÔTE — âge en heures du dernier succès de identite-sauvegarde (vide si inconnu).
_m24p_e25_age() {
  local t
  t="$(_m24d_ssh "$1" "sudo -n cat /var/lib/identite-sauvegarde/dernier-succes" | awk 'NR == 1 {print $1}')"
  [[ "$t" =~ ^[0-9]+$ ]] && echo $(( ($(date +%s) - t) / 3600 ))
}

for _m24p_e25_h in "$_M24D_IDP" "$_M24D_IPA"; do
  check_ssh "$_m24p_e25_h : minuterie identite-sauvegarde.timer active" "$_m24p_e25_h" \
    "systemctl is-active --quiet identite-sauvegarde.timer && systemctl is-enabled --quiet identite-sauvegarde.timer"
  check_cmd "$_m24p_e25_h : dernière sauvegarde réussie il y a moins de 26 h" \
    _m24p_compare "$(_m24p_e25_age "$_m24p_e25_h")" '<' 26
  check_ssh_output "$_m24p_e25_h : identifiants S3 en root:root 600" "$_m24p_e25_h" '^root:root:600$' \
    "sudo -n stat -c '%U:%G:%a' /etc/identite-sauvegarde/s3.env"
  check_ssh_output "$_m24p_e25_h : aucune archive claire laissée dans /var/backups/identite" "$_m24p_e25_h" '^0$' \
    "sudo -n find /var/backups/identite -type f \\( -name '*.dump' -o -name '*.tar' \\) 2>/dev/null | wc -l"
  check_ssh_output "$_m24p_e25_h : l'objet envoyé est chiffré (.age)" "$_m24p_e25_h" '\.age$' \
    "sudo -n awk 'NR == 1 {print \$2}' /var/lib/identite-sauvegarde/dernier-succes"
done

# --- PBS : stockage par1/identite et tâche identite-nuit ---------------------------------------------------
_m24p_e25_sto="$(remote "$_M24P_PVE" "pvesh get /storage/pbs-par2-identite --output-format json" 2>/dev/null || true)"
check_cmd "Proxmox : stockage pbs-par2-identite (espace de noms par1/identite)" _m24d_json "$_m24p_e25_sto" \
  '.type == "pbs" and .namespace == "par1/identite"'
_m24p_e25_noeud="$(remote "$_M24P_PVE" "hostname -s" 2>/dev/null || true)"
_m24p_e25_contenu="$(remote "$_M24P_PVE" "pvesh get /nodes/${_m24p_e25_noeud:-pve01}/storage/pbs-par2-identite/content --content backup --output-format json" 2>/dev/null || true)"
# shellcheck disable=SC2016  # $v est une variable de jq
for _m24p_e25_vm in 1030 1031; do
  check_cmd "PBS par1/identite : sauvegarde de la VM $_m24p_e25_vm de moins de 48 h" _m24d_json "$_m24p_e25_contenu" \
    'any(.[]; (.vmid | tostring) == $v and .ctime > (now - 172800))' --arg v "$_m24p_e25_vm"
done
_m24p_e25_taches="$(remote "$_M24P_PVE" "pvesh get /cluster/backup --output-format json" 2>/dev/null || true)"
check_cmd "Proxmox : tâche identite-nuit vers pbs-par2-identite (VMs 1030 et 1031)" _m24d_json "$_m24p_e25_taches" \
  'any(.[]; .id == "identite-nuit" and .storage == "pbs-par2-identite"
     and ((.vmid // "") | split(",") | index("1030") != null and index("1031") != null))'
# shellcheck disable=SC2016  # $ex est une variable de jq
check_cmd "Proxmox : lab-nuit ne sauvegarde plus 1030 ni 1031" _m24d_json "$_m24p_e25_taches" \
  '[.[] | select(.id == "lab-nuit")] | length == 1 and all(.[];
     (((.exclude // "") | split(",")) as $ex | ($ex | index("1030") != null and index("1031") != null))
     or ((.all // 0) != 1 and (.pool // "") == "" and ((.vmid // "") | split(",") | index("1030") == null and index("1031") == null)))'

# --- RB-243 et nettoyage -----------------------------------------------------------------------------------
_m24p_e25_rb="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -Ei 'RB-243' | head -n 1 || true)"
_m24p_e25_rb_c=""
[[ -n "$_m24p_e25_rb" ]] && _m24p_e25_rb_c="$(_m24p_doc "$_m24p_e25_rb")"
check_cmd "RB-243 (restauration de l'identité) sur main de plateforme/medisphere" test -n "$_m24p_e25_rb_c"
check_cmd "RB-243 : un RTO mesuré (en minutes) et la preuve de la restauration par le kid" \
  _m24p_tous "$_m24p_e25_rb_c" 'RTO.*[0-9]+ ?min' '\bkid\b'
check_cmd "RB-243 : rempli (aucune valeur <N> ou <AAAA-MM-JJ> laissée)" _m24p_sans_gabarit "$_m24p_e25_rb_c"
check_cmd "Proxmox : la VM de restauration d'essai 2242 (idp-resto) n'existe plus" _m24p_vm_absente 2242
