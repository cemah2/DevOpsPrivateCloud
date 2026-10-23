# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S09.sh — F4-S09 « Plan de migration du VMware d'InfoGér » (RED publié) : présence de l'export
# et contenu minimal des livrables. Lecture seule (pve01 en root, GitLab en GET).

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"

title "F4-S09 — Plan de migration du VMware d'InfoGér"
require_cmd jq curl ssh

if _f4g_export_dir >/dev/null 2>&1; then
  for _f4_s09_vm in legacy-rdv01 ftp-part01 stats01; do
    # F4-S14 efface l'export de legacy-rdv01 (données de santé) après la sauvegarde finale.
    if [[ "$_f4_s09_vm" == legacy-rdv01 ]] && ! _f4g_export_conforme legacy-rdv01 && _f4g_decommissionnee 3401; then
      skip "export de legacy-rdv01" "effacé au décommissionnement (F4-S14, CHG-3414)"
      continue
    fi
    check_cmd "export de $_f4_s09_vm présent sur pve01, complet et conforme à son manifeste" _f4g_export_conforme "$_f4_s09_vm"
  done
else
  check_cmd "stockage d'export ${_f4g_stockage} lisible sur pve01 (pvesh get /storage)" false
fi

check_cmd "docs/changements/migration-vmware.md sur main : inventaire, dépendance stats01 → legacy-rdv01, vagues, re-adressage, fenêtres, retour arrière" \
  _f4g_doc "$_f4g_doc_dir" '^migration-vmware\.md$' 'stats01' 'legacy-rdv01' 'ftp-part01' '3306|base de (donn|legacy)' \
  'vague' '10\.10\.20\.44' '10\.10\.20\.45' '10\.10\.20\.46' 'fen(e|ê)tre' 'retour arri' 'manifeste|sha-?256'
check_cmd "docs/changements/inventaire-reel.csv sur main (adresse réelle de stats01 découverte)" \
  _f4g_doc "$_f4g_doc_dir" '^inventaire-reel\.csv$' 'legacy-rdv01' 'ftp-part01' 'stats01' '192\.168\.50\.40'
check_cmd "le mot de passe de 2014 de Legacy-RDV n'apparaît pas dans migration-vmware.md" \
  _f4g_doc_sans "$_f4g_doc_dir" '^migration-vmware\.md$' 'InfoGer2014!'
check_cmd "le mot de passe de 2014 de Legacy-RDV n'apparaît pas dans inventaire-reel.csv" \
  _f4g_doc_sans "$_f4g_doc_dir" '^inventaire-reel\.csv$' 'InfoGer2014!'
check_cmd "fiche CHG-3410 (migration des VMs) sur main : risque, fenêtre, retour arrière" \
  _f4g_doc "$_f4g_doc_dir/fiches" '^CHG-3410' 'risque' 'fen(e|ê)tre' 'retour arri'
