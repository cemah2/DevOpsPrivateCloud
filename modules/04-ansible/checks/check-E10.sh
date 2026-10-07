# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E10.sh — M04-E10 : Premier rôle : base
# À lancer depuis adm01. Lecture seule : structure du rôle, état des hôtes (timedatectl,
# journald, apt-config, clés autorisées), playbook en --check (une à deux minutes).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E10 — Premier rôle : base"
require_cmd git jq curl ssh-keygen

# --- Le rôle et le playbook ------------------------------------------------------------------
check_cmd "roles/base : tasks, defaults et meta présents" _m04o_role_complet base
check_cmd "roles/base publié sur main" _m04_fichier_main roles/base/tasks/main.yml
check_cmd "playbooks/socle-base.yml publié sur main" _m04_fichier_main playbooks/socle-base.yml
check_cmd "socle-base.yml applique le rôle base au groupe socle" \
  bash -c 'grep -Eq "^[[:space:]]*hosts:[[:space:]]*socle[[:space:]]*$" "$1" && grep -Eq "role:[[:space:]]*base\b|^[[:space:]]+-[[:space:]]+base[[:space:]]*$" "$1"' \
  _ "$_M04_SRC/playbooks/socle-base.yml"
for _m04o_pb in trousse-diagnostic identite-hotes chrony-client; do
  check_cmd "playbooks/$_m04o_pb.yml retiré de main (repris par le rôle)" \
    _m04o_absent_main "playbooks/$_m04o_pb.yml"
done
check_cmd "aucune variable trousse_* ne subsiste dans l'inventaire" \
  bash -c '! grep -rEq "^[[:space:]]*trousse_paquets" "$1/inventories"' _ "$_M04_SRC"

# --- L'état obtenu sur les hôtes --------------------------------------------------------------
for _m04o_h in $_M04_SOCLE; do
  check_ssh_output "$_m04o_h : fuseau horaire Europe/Paris" "$_m04o_h" '^Europe/Paris$' \
    'timedatectl show -p Timezone --value'
  check_ssh_output "$_m04o_h : journal persistant (configuration effective)" "$_m04o_h" '^Storage=persistent' \
    'systemd-analyze cat-config systemd/journald.conf'
  check_ssh "$_m04o_h : journaux présents dans /var/log/journal" "$_m04o_h" \
    'test -n "$(ls -A /var/log/journal 2>/dev/null)"'
  check_ssh_output "$_m04o_h : mises à jour automatiques activées" "$_m04o_h" \
    'APT::Periodic::Unattended-Upgrade "1";' 'apt-config dump APT::Periodic::Unattended-Upgrade'
  check_ssh "$_m04o_h : unattended-upgrades limité à la sécurité" "$_m04o_h" \
    'o="$(apt-config dump Unattended-Upgrade::Origins-Pattern)"; grep -q -- "-security" <<<"$o" && ! grep -Eq "label=Debian\"" <<<"$o"'
  check_ssh "$_m04o_h : fait local /etc/ansible/facts.d/medisphere.fact lisible (JSON)" "$_m04o_h" \
    'python3 -m json.tool /etc/ansible/facts.d/medisphere.fact >/dev/null'
done

# Clé de adm01 autorisée pour admin sur les hôtes joints en SSH (empreinte comparée).
_m04o_emp="$(ssh-keygen -lf "$HOME/.ssh/id_ed25519.pub" 2>/dev/null | awk '{print $2}')" || true
for _m04o_h in $_M04O_DISTANTS; do
  check_ssh "$_m04o_h : la clé de admin@adm01 est autorisée pour admin" "$_m04o_h" \
    "ssh-keygen -lf ~/.ssh/authorized_keys 2>/dev/null | grep -qF -- '${_m04o_emp:-absente}'"
done

# --- Chrony : clients sur la passerelle, serveur intact ---------------------------------------
check_ssh_output "dns01 : chrony synchronisé sur 10.10.20.1 (^*)" dns01 '^\^\*[[:space:]]+10\.10\.20\.1[[:space:]]' \
  'chronyc -n sources'
check_ssh_output "gw01 : sert toujours le temps au lab (accès autorisé depuis 10.10.20.10)" gw01 \
  '208 Access allowed' 'sudo -n chronyc accheck 10.10.20.10'

# --- Idempotence ------------------------------------------------------------------------------
_m04o_sortie="$(_m04_simuler playbooks/socle-base.yml)"
for _m04o_h in $_M04_SOCLE; do
  check_cmd "--check de socle-base.yml sur $_m04o_h : aucun changement, aucun échec" \
    _m04_recap "$_m04o_sortie" "$_m04o_h"
done
