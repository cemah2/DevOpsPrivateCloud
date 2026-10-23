# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S08.sh — F5-S08 « Panne : la reprise qui ne reprend pas » (BF, avant le sinistre, depuis adm01) :
# PAR2 de nouveau prêt quelle que soit la variante injectée (filer.sync actif sur s3-02, nœud de k8s-par2
# planifiable, bao-par2 démarrable, réplique de PAR2 saine, dns03 et reg02 joignables) et compte rendu de
# la répétition (INC-6108) publié. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S08 — Panne : la reprise qui ne reprend pas"
require_cmd kubectl jq curl dig ssh

check_cmd "s3-02 : la réplication filer.sync depuis s3-01 tourne (unité active)" _f5p_filersync_ok
check_cmd "k8s-par2 : $_F5E_NOEUD_PAR2 est Ready et planifiable" _f5e_p_noeud2
check_cmd "hp01 : la VM $_F5E_VMID_BAO_PAR2 (bao-par2) ne porte aucun verrou" _f5e_p_bao2
_f5_s08_bao_arrete() { _f5p_sur "$_f5e_hp01" "qm status $_F5E_VMID_BAO_PAR2" 2>/dev/null | grep -q 'status: stopped'; }
check_cmd "hp01 : bao-par2 est arrêté (veille) après la répétition" _f5_s08_bao_arrete
_f5_s08_sans_3501() { [[ "$(_f5p_vm_etat 3501)" == absente ]]; }
check_cmd "hp01 : la restauration d'essai de kms01 (VM 3501) a été détruite après la répétition" _f5_s08_sans_3501
check_cmd "k8s-par2 : $_F5E_CNPG_PAR2 est une réplique saine" _f5e_p_cnpg2_replique
check_cmd "dns03 répond pour medisphere.internal" _f5e_p_dns03
check_cmd "reg02 répond sur /v2/" _f5e_p_reg02
check_cmd "compte rendu de la répétition publié (INC-6108 : constat, cause, réparation, prévention)" \
  _f5p_doc_motif "exercices/$_f5e_exercice" '^repetition' 'INC-6108' 'cause' 'r(é|e)par|correct' 'pr(é|e)vention|action'
