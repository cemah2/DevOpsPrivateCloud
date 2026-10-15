# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M16-E39 « Panne : la sauvegarde Velero échoue » : emplacement de sauvegarde
# disponible vers velero-k8s-par1 avec sa CA, node-agent sur chaque travailleur, et une sauvegarde
# de wb-essais terminée (Completed) APRÈS la dernière injection de la panne. Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E39 — Velero sauvegarde à nouveau"
require_cmd kubectl jq

_m16_e39_bsl="$(_m16x_j backupstoragelocations.velero.io -n velero)"
_m16_e39_sel='([.items[] | select(.spec.default == true)] + [.items[] | select(.spec.objectStorage.bucket == "velero-k8s-par1")])[0]'
check_cmd "emplacement de sauvegarde par défaut : compartiment velero-k8s-par1" _m16x_q "$_m16_e39_bsl" \
  "$_m16_e39_sel | .spec.objectStorage.bucket == \"velero-k8s-par1\""
check_cmd "emplacement de sauvegarde : CA de la PKI MédiSphère fournie (caCert)" _m16x_q "$_m16_e39_bsl" \
  "$_m16_e39_sel | (.spec.objectStorage.caCert // \"\") | length > 0"
check_cmd "emplacement de sauvegarde : Available (dernière validation réussie)" _m16x_q "$_m16_e39_bsl" \
  "$_m16_e39_sel | .status.phase == \"Available\""
check_cmd "node-agent prêt sur chaque travailleur" _m16x_ds_complet velero node-agent

_m16_e39_t="$(_m16x_injection E39)"
check_cmd "une sauvegarde incluant wb-essais terminée (Completed) depuis l'incident" _m16x_cree_apres \
  "$(_m16x_j backups.velero.io -n velero)" "$_m16_e39_t" \
  '.status.phase == "Completed" and (((.spec.includedNamespaces // []) | length == 0) or ((.spec.includedNamespaces // []) | index("wb-essais") or index("*")))'
check_cmd "panne M16-E39 close (lab/bin/break 16 39 --annuler après réparation)" _m16x_aucune_panne_active E39
