# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E29.sh — M12-E29 « Sauvegarder et restaurer les données des conteneurs »
# Lecture seule : unités et secrets sur ctr01 (systemctl show, stat), conteneurs et volumes de
# ctr01, datastore de pbs01 (find en root), tâches de sauvegarde de pve01 (pvesh get), fichiers
# sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E29 — Sauvegarde des données des conteneurs"
require_cmd jq

title "Sur ctr01"
check_ssh "timer wb-backup-conteneurs actif" ctr01 "systemctl is-active --quiet wb-backup-conteneurs.timer"
check_ssh_output "timer à 01:40" ctr01 '01:40' "systemctl show -p TimersCalendar wb-backup-conteneurs.timer"
check_ssh_output "dernier passage réussi" ctr01 '^ExecMainExitTimestamp=.+ ExecMainStatus=0 Result=success$' \
  "systemctl show -p Result -p ExecMainStatus -p ExecMainExitTimestamp wb-backup-conteneurs.service | sort | paste -sd ' '"
check_ssh_output "secrets PBS root:root en 600" ctr01 '^root:600 root:600$' \
  "sudo -n stat -c '%U:%a' /etc/wb-backup/pbs-ctr01.env /etc/wb-backup/pbs-ctr01.key | paste -sd ' '"
check_ssh_output "configuration : au moins un export de base déclaré" ctr01 'WB_BASES=\("[^"]+\|[^"]+\|[^"]+"' \
  "sudo -n cat /etc/wb-backup/conteneurs.conf"
# La base de la recette doit apparaître : une liste vide (hôte injoignable) ne prouve rien.
_m12_e29_objets="$(_m12p_docker ctr01 "ps -a --format '{{.Names}}'"; _m12p_docker ctr01 "volume ls --format '{{.Name}}'")"
check_cmd "aucun conteneur ni volume restau-* ne reste" \
  bash -c 'grep -q "^mediagenda-db-1$" <<<"$1" && ! grep -q "^restau-" <<<"$1"' _ "$_m12_e29_objets"

title "PBS et sauvegarde de la VM"
check_cmd "pbs01 : sauvegarde de ctr01 dans par1/conteneurs de moins de 48 h (exports de base)" \
  _m12p_pbs_recent ctr01 'bases.pxar.didx' 48
check_ssh_output "pve01 : la tâche lab-nuit couvre le pool lab (donc ctr01)" "${WB_PVE_HOST:-pve01}" '^lab$' \
  "pvesh get /cluster/backup --output-format json | jq -r '.[] | select(.id == \"lab-nuit\") | .pool // empty'"

title "Dans le code"
check_cmd "plateforme/ansible : rôle sauvegarde_conteneurs sur main" \
  _m12p_arbre_contient plateforme/ansible '^roles/sauvegarde_conteneurs/'
check_cmd "test de restauration consigné (RTO)" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/tests/restauration-conteneurs.md 'RTO' 'RPO'
check_cmd "RB-121 sur main" _m12p_arbre_contient plateforme/medisphere '^docs/conteneurs/runbooks/RB-121'
