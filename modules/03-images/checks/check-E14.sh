# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E14.sh — M03-E14 « Tester automatiquement une image »
# Le script de test existe, est publié sur main, est propre, couvre les points du ticket
# PLAT-452 et ne laisse rien derrière lui. Le check ne lance PAS le test (il crée des VMs) :
# la preuve d'exécution est le pipeline de M03-E15 et ton journal.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E14 — Tester automatiquement une image"
require_cmd jq ssh curl shellcheck
_m03_charger
_m03_t="$_M03_SRC/tests/tester-image.sh"

check_cmd "tests/tester-image.sh présent et exécutable (clone local)" test -x "$_m03_t"
check_cmd "tests/tester-image.sh sans remarque ShellCheck" shellcheck -x "$_m03_t"
check_cmd "tests/tester-image.sh publié sur main" _m03_fichier_main tests/tester-image.sh
check_output "--help décrit l'usage" '[Uu]sage' "$_m03_t" --help
_m03_e14_usage() { local rc=0; "$_m03_t" >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]]; }
check_cmd "sans argument : refus avec un code d'usage (2)" _m03_e14_usage

title "Couverture du test (contenu du script)"
_m03_e14_couvre() { grep -Eq -- "$1" "$_m03_t"; }
check_cmd "état de cloud-init (cloud-init status)" _m03_e14_couvre 'cloud-init status'
check_cmd "unicité de l'identité machine (machine-id)" _m03_e14_couvre 'machine-id'
check_cmd "clés d'hôte SSH régénérées (empreinte)" _m03_e14_couvre 'ssh-keygen -l|ssh_host_'
check_cmd "synchronisation du temps (chronyc)" _m03_e14_couvre 'chronyc'
check_cmd "configuration effective de sshd (sshd -T)" _m03_e14_couvre 'sshd -T'
check_cmd "agent QEMU" _m03_e14_couvre 'qemu-guest-agent|agent/ping|guest cmd'
check_cmd "autorité de certification MédiSphère" _m03_e14_couvre 'medisphere-provisoire'
check_cmd "destruction des VMs de test même en cas d'échec (trap)" _m03_e14_couvre 'trap '

title "Hygiène"
check_cmd "aucune VM de test oubliée (2030-2033)" _m03_aucune_vm 2030 2033
check_cmd "aucun template d'essai oublié (9090-9099)" _m03_aucune_vm 9090 9099
_m03_a_current() { [[ -n "$(_m03_current "$1")" ]]; }
check_cmd "une seule image dorée Debian « current » (cible du test)" _m03_a_current debian13
