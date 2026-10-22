# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016
#
# check-E30.sh — M25-E30 « Comparer : HashiCorp Vault 2.2 » : compte rendu sur main (licence,
# configuration, fonctions, clients, migration) ; bao-essai (2251) détruite ; plus de flux depuis
# 10.10.99.51 vers kms01 (bordure, pare-feu local).
# À lancer depuis adm01. Lecture seule : GitLab, qm status.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E30 — Comparer : HashiCorp Vault 2.2"
require_cmd jq curl

check_cmd "docs/securite/secrets/comparatif-vault.md sur main : licence, configuration, fonctions, clients, migration" \
  _m25p_doc "$_M25P_DOC" docs/securite/secrets 'comparatif-vault\.md$' 25 'BUSL' 'disable_mlock' 'namespace|espaces? de noms' \
  'audit' 'instantan' 'ESO|external secrets' 'hashicorp/vault|opentofu'
check_cmd "bao-essai (VMID 2251) n'existe plus" _m25p_vm_absente 2251
check_cmd "matrice de la bordure (main) : plus de flux depuis 10.10.99.51" \
  _m25p_fichier_sans "$_M25P_ANSIBLE" inventories/lab/group_vars/role_routeur/pare_feu.yml '^[^#]*10\.10\.99\.51'
check_cmd "pare-feu local de kms01 (main) : plus de flux depuis vsandbox" \
  _m25p_fichier_sans "$_M25P_ANSIBLE" inventories/lab/host_vars/kms01/pare_feu_local.yml '^[^#]*10\.10\.99\.'
