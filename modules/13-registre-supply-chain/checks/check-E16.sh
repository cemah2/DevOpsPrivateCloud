# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E16.sh — M13-E16 « Superviser et mettre à jour Harbor »
# Lecture seule : santé et version (API), métriques (HTTP), sonde sur adm01 (systemctl, exécution de la
# sonde, qui ne fait que des lectures), code et documentation (API GitLab).

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E16 — Superviser et mettre à jour Harbor"
require_cmd jq curl

title "État et version"
check_cmd "/api/v2.0/health : tous les composants « healthy »" _m13p_sante
check_cmd "Harbor de reg01 en $_M13P_VERSION (dernière version corrective attendue, WB_M13_HARBOR_VERSION)" _m13p_version_ok
check_output "métriques servies sur http://reg01.par1.medisphere.internal:9090/metrics" '^harbor_' \
  curl -sf --max-time "$WB_TIMEOUT" http://reg01.par1.medisphere.internal:9090/metrics

title "Sonde ms-verif-registre (adm01)"
check_cmd "ms-verif-registre installé sous /usr/local/bin" test -x /usr/local/bin/ms-verif-registre
check_cmd "configuration /usr/local/etc/ms-verif-registre.conf présente" test -r /usr/local/etc/ms-verif-registre.conf
check_cmd "secret du robot de supervision : admin, 600" \
  bash -c '[[ "$(stat -c %U:%a /usr/local/etc/ms-verif-registre.secret 2>/dev/null)" == admin:600 ]]'
check_cmd "ms-verif-registre.timer actif" systemctl is-active -q ms-verif-registre.timer
check_output "… toutes les 5 minutes" '0/5|\*:0/5|\*/5' systemctl show -p TimersCalendar ms-verif-registre.timer
check_output "le service déclenche ms-alerte@… en cas d'échec" 'ms-alerte@' systemctl show -p OnFailure ms-verif-registre.service
check_cmd "la sonde rend 0 sur le registre sain" timeout 120 /usr/local/bin/ms-verif-registre --quiet
_m13_e16_usage() { local rc=0; timeout 20 /usr/local/bin/ms-verif-registre --option-inconnue >/dev/null 2>&1 || rc=$?; ((rc == 2)); }
check_cmd "une option inconnue rend 2" _m13_e16_usage
check_cmd "tests bats de la sonde sur main de plateforme/outils" \
  _m13p_fichier_motifs plateforme/outils tests/bats/ms-verif-registre.bats '@test'
check_cmd "dernier pipeline de main de plateforme/outils réussi" _m13p_pipeline_ok plateforme/outils

title "Mise à jour"
check_cmd "playbooks/harbor-mise-a-jour.yml sur main de plateforme/ansible (prepare migrate)" \
  _m13p_fichier_motifs plateforme/ansible playbooks/harbor-mise-a-jour.yml 'migrate' 'harbor'
check_cmd "docs/registre/tests/montee-version-harbor.md (répétition, retour arrière)" \
  _m13p_doc_main docs/registre/tests/montee-version-harbor.md '2\.15' 'retour arri'
check_cmd "RB-132 publié dans docs/registre/runbooks/" _m13p_doc_prefixe docs/registre/runbooks RB-132
