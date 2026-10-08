# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E31.sh — M09-E31 « Capacité et surallocation »
# À lancer depuis adm01. Lecture seule : exécutions de ms-capacite-cluster (qui ne fait que lire
# l'API), paramètres du module ZFS et état de ksmtuned sur les nœuds, inventaire du cluster, GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E31 — Capacité et surallocation"
require_cmd jq ssh
_m09p_charger

_m09_e31_outil=/usr/local/bin/ms-capacite-cluster

title "L'outil"
check_cmd "ms-capacite-cluster installé" test -x "$_m09_e31_outil"
check_cmd "configuration installée (/usr/local/etc/ms-capacite-cluster.conf)" test -r /usr/local/etc/ms-capacite-cluster.conf
check_output "une demande de 1×512 Mio est acceptée (code 0)" '^0$' \
  bash -c 'timeout 120 "$1" --quiet --demande 1x512 >/dev/null 2>&1; echo $?' _ "$_m09_e31_outil"
check_output "une demande de 20×2048 Mio est refusée (code 1)" '^1$' \
  bash -c 'timeout 120 "$1" --quiet --demande 20x2048 >/dev/null 2>&1; echo $?' _ "$_m09_e31_outil"
check_output "une demande mal formée donne le code 2" '^2$' \
  bash -c 'timeout 30 "$1" --demande vingt >/dev/null 2>&1; echo $?' _ "$_m09_e31_outil"
check_cmd "plateforme/outils : tests bats de ms-capacite-cluster sur main" \
  _m09p_fichier_existe plateforme/outils tests/bats/ms-capacite-cluster.bats

title "Mémoire des nœuds"
_m09_e31_doc="$(_m09p_doc_contenu "" capacite-hv-par1 2>/dev/null || true)"
for _m09_e31_n in "${_M09P_NOEUDS[@]}"; do
  _m09_e31_arc="$(_m09p_hv "$_m09_e31_n" 'cat /sys/module/zfs/parameters/zfs_arc_max' 2>/dev/null || echo inconnu)"
  if [[ "$_m09_e31_arc" =~ ^[1-9][0-9]*$ ]]; then
    check_cmd "$_m09_e31_n : taille maximale du cache ZFS explicite ($((_m09_e31_arc / 1048576)) Mio)" true
  else
    check_output "$_m09_e31_n : cache ZFS non limité — décision justifiée dans le document de capacité" \
      'zfs_arc_max' printf '%s\n' "$_m09_e31_doc"
  fi
  check_ssh "$_m09_e31_n : ksmtuned actif" "root@$_m09_e31_n.$_M09P_ZONE" 'systemctl is-active --quiet ksmtuned'
done

title "Document et ménage"
check_output "docs/virtualisation/capacite-hv-par1.md sur main, avec le calcul N+1" 'N\+1' printf '%s\n' "$_m09_e31_doc"
for _m09_e31_id in 123 124 125 126; do
  check_cmd "VM $_m09_e31_id détruite" _m09p_vm_cluster_absente "$_m09_e31_id"
done
