# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E26.sh — M12-E26 « Durcir le moteur : socket, userns-remap, Docker sans privilège »
# Lecture seule : getent, ss, docker info, docker network inspect, /proc d'un conteneur EXISTANT
# (le registre de travail), auditctl -l, ausearch ; fichiers sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E26 — Durcir le moteur (ctr01, runner02)"
require_cmd jq curl

title "Accès au démon"
check_ssh_output "ctr01 : le groupe docker ne contient que admin" ctr01 '^(admin)?$' \
  "getent group docker | cut -d: -f4"
check_ssh_output "runner02 : le groupe docker est vide" runner02 \
  '^$' "getent group docker | cut -d: -f4"
check_ssh_output "ctr01 : les comptes demo-docker et essai-rootless n'existent plus" ctr01 '^ABSENTS$' \
  "getent passwd demo-docker essai-rootless >/dev/null || echo ABSENTS"
for _m12_e26_h in ctr01 runner02; do
  check_ssh_output "$_m12_e26_h : aucun démon de conteneurs n'écoute en TCP" "$_m12_e26_h" '^AUCUN$' \
    "sudo -n ss -Hltnp | grep -Eq '\"(dockerd|containerd)\"' && echo TCP || echo AUCUN"
done

title "Options du démon (ctr01)"
_m12_e26_info="$(_m12p_docker ctr01 "info --format '{{json .}}'")"
check_cmd "live-restore actif" _m12p_jq "$_m12_e26_info" '.LiveRestoreEnabled == true'
check_cmd "userns-remap inactif (décision E26)" _m12p_jq "$_m12_e26_info" '(.SecurityOptions // []) | any(test("name=userns")) | not'
check_cmd "stockage d'images containerd toujours utilisé" _m12p_jq "$_m12_e26_info" \
  '(.DriverStatus // []) | any(.[1] | test("io.containerd.snapshotter"))'
check_output "réseau bridge par défaut : communication entre conteneurs désactivée" '^false$' \
  _m12p_docker ctr01 "network inspect bridge --format '{{index .Options \"com.docker.network.bridge.enable_icc\"}}'"
check_ssh_output "daemon.json : no-new-privileges par défaut" ctr01 '^true$' \
  "jq -r '.\"no-new-privileges\"' /etc/docker/daemon.json"
_m12_e26_reg="$(_m12p_ctr_service ctr01 registre registre)"
check_output "un conteneur sans l'option (registre) a NoNewPrivs à 1" '^NoNewPrivs:[[:space:]]+1$' \
  _m12p_docker ctr01 "exec ${_m12_e26_reg:-registre-absent} cat /proc/1/status"
check_http "le registre de travail répond (401 sans identifiants)" "https://$_M12P_REGISTRE/v2/" 401 --cacert "$_M12P_RACINE"

title "Audit"
check_ssh_output "règles d'audit chargées (clé docker)" ctr01 '-k docker' "sudo -n auditctl -l"
check_ssh_output "un événement d'audit « docker » de moins de 7 jours" ctr01 '^EVENEMENT$' \
  "sudo -n ausearch -k docker -ts \$(date -d '7 days ago' '+%m/%d/%Y') >/dev/null 2>&1 && echo EVENEMENT || echo AUCUN"

title "Dans le code"
check_cmd "plateforme/ansible : rôle audit_conteneurs sur main" \
  _m12p_arbre_contient plateforme/ansible '^roles/audit_conteneurs/'
check_cmd "plateforme/ansible : live-restore et icc dans les variables de docker_engine" \
  _m12p_doc_main plateforme/ansible inventories/lab/group_vars/role_docker/docker_engine.yml 'live-restore' 'icc'
check_cmd "durcissement-execution.md : section Moteur (socket, userns-remap)" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/durcissement-execution.md 'userns' 'socket'
