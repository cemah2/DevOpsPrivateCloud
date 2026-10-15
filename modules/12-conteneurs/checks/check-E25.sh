# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes, évalués ailleurs
#
# check-E25.sh — M12-E25 « SELinux et conteneurs sur Rocky Linux »
# Lecture seule sur ctr03 : getenforce, semanage fcontext -l -C, semodule -l, ls -Zd, podman
# inspect du compte app, ausearch ; fichiers sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E25 — SELinux et conteneurs (ctr03)"
require_cmd jq

check_ssh_output "ctr03 : SELinux en mode enforcing" ctr03 '^Enforcing$' getenforce
check_cmd "ctr03 : Podman du compte app voit SELinux actif" \
  bash -c '[[ "$1" == true ]]' _ "$(_m12p_podman ctr03 "info --format '{{.Host.Security.SELinuxEnabled}}'")"

title "Étiquettes des données"
check_ssh_output "règle locale semanage fcontext pour /srv/legacy-rdv/uploads (container_file_t)" ctr03 \
  '^/srv/legacy-rdv/uploads.*container_file_t' "sudo -n semanage fcontext -l -C"
check_ssh_output "/srv/legacy-rdv/uploads porte container_file_t" ctr03 ':container_file_t:' \
  "ls -Zd /srv/legacy-rdv/uploads"
check_ssh_output "/srv/legacy-rdv/uploads : l'étiquette est celle de la politique (restorecon ne changerait rien)" ctr03 \
  '^RIEN$' "out=\$(sudo -n restorecon -n -v /srv/legacy-rdv/uploads 2>&1); [ -z \"\$out\" ] && echo RIEN || echo \"\$out\""
check_ssh_output "/home/app/depot-infoger a gardé user_home_t" ctr03 ':user_home_t:' \
  "sudo -n ls -Zd /home/app/depot-infoger"

title "Politique dédiée (udica)"
check_ssh_output "module legacy_rdv chargé" ctr03 '^legacy_rdv$' \
  "sudo -n semodule --list-modules=standard | awk '{print \$1}'"
_m12_e25_lab="$(_m12p_podman ctr03 "inspect legacy-rdv --format '{{.State.Status}} {{.ProcessLabel}}'")"
check_output "le conteneur legacy-rdv du compte app tourne avec le type legacy_rdv.process" \
  '^running [^ ]*:legacy_rdv\.process:' echo "$_m12_e25_lab"
check_output "le conteneur legacy-rdv est lancé par son unité Quadlet" 'legacy-rdv\.service' \
  _m12p_podman ctr03 "inspect legacy-rdv --format '{{index .Config.Labels \"PODMAN_SYSTEMD_UNIT\"}}'"
check_ssh_output "unité Quadlet : SecurityLabelType, ni SecurityLabelDisable ni :z/:Z" ctr03 '^CONFORME$' \
  "f=/home/app/.config/containers/systemd/legacy-rdv.container; sudo -n grep -q '^SecurityLabelType=legacy_rdv.process' \$f \
   && ! sudo -n grep -Eq '^SecurityLabelDisable=|^Volume=.*:[^:]*[zZ][^:/]*$' \$f && echo CONFORME"
# Refus SELinux pour ce type depuis le dernier démarrage de l'unité.
check_ssh_output "aucun refus SELinux pour legacy_rdv.process depuis le démarrage de l'unité" ctr03 '^AUCUN$' "
  t=\$(sudo -n -u app env XDG_RUNTIME_DIR=/run/user/$_M12P_APP_UID systemctl --user show -p ActiveEnterTimestamp --value legacy-rdv.service 2>/dev/null)
  [ -n \"\$t\" ] || exit 0
  d=\$(LC_ALL=C date -d \"\$t\" '+%m/%d/%Y %H:%M:%S') || exit 0
  # Format de date de ausearch -ts : celui de LC_TIME (on impose C des deux côtés).
  if sudo -n env LC_ALL=C ausearch -m AVC,USER_AVC -ts \$d --context legacy_rdv.process >/dev/null 2>&1; then echo REFUS; else echo AUCUN; fi"

title "Dans le code"
check_cmd "plateforme/ansible : rôle selinux_conteneurs et module legacy_rdv.cil sur main" \
  _m12p_arbre_contient plateforme/ansible 'roles/selinux_conteneurs/.*legacy_rdv\.cil$'
check_cmd "durcissement-execution.md : section SELinux" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/durcissement-execution.md 'udica' 'fcontext'
