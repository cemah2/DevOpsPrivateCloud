# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E13.sh — M04-E13 : Inventaire dynamique Proxmox
# À lancer depuis adm01. Lecture seule : comptes, rôles et ACL sur pve01 (pveum en lecture),
# fichier d'accès, inventaire produit par ansible-inventory (aucun hôte n'est contacté).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E13 — Inventaire dynamique Proxmox"
require_cmd git jq curl stat

_m04o_pve="${WB_PVE_HOST:-pve01}"

# --- Compte, jeton, rôles et ACL sur pve01 --------------------------------------------------------
check_ssh "pve01 : utilisateur wb-ansible@pve" "$_m04o_pve" \
  'pveum user list --output-format json | grep -q "\"wb-ansible@pve\""'
check_ssh "pve01 : jeton « ansible » avec séparation des privilèges et date d'expiration" "$_m04o_pve" \
  'pveum user token list wb-ansible@pve --output-format json | perl -MJSON::PP -0777 -ne '\''exit !(grep { $_->{tokenid} eq "ansible" && $_->{privsep} && $_->{expire} } @{decode_json($_)})'\'''
check_ssh "pve01 : rôle WBAnsible (VM.Audit, VM.GuestAgent.Audit, Pool.Audit)" "$_m04o_pve" \
  'p="$(pveum role list --output-format json | perl -MJSON::PP -0777 -ne '\''print map { $_->{privs} } grep { $_->{roleid} eq "WBAnsible" } @{decode_json($_)}'\'')"; for x in VM.Audit VM.GuestAgent.Audit Pool.Audit; do grep -qw -- "$x" <<<"$p" || exit 1; done'
check_ssh "pve01 : WBAnsible ne donne aucun droit d'administration (permissions, nœud, utilisateurs)" "$_m04o_pve" \
  '! pveum role list --output-format json | perl -MJSON::PP -0777 -ne '\''exit !(grep { $_->{roleid} eq "WBAnsible" && $_->{privs} =~ /Permissions\.Modify|Sys\.Modify|User\.Modify|Realm\./ } @{decode_json($_)})'\'''
check_ssh "pve01 : le jeton voit les VMs du pool lab (VM.Audit sur /vms/1002)" "$_m04o_pve" \
  'pveum user token permissions wb-ansible@pve ansible --path /vms/1002 --output-format json | grep -q "VM.Audit"'
check_ssh "pve01 : le jeton ne voit RIEN hors du pool lab (aucun VM.Audit sur /vms/999999)" "$_m04o_pve" \
  '! pveum user token permissions wb-ansible@pve ansible --path /vms/999999 --output-format json | grep -q "VM.Audit"'
check_ssh "pve01 : sur « / », le jeton n'a que Sys.Audit (exigé par /cluster/status)" "$_m04o_pve" \
  'j="$(pveum user token permissions wb-ansible@pve ansible --path / --output-format json)"; grep -q "Sys.Audit" <<<"$j" && ! grep -Eq "VM\.|Datastore\.|Sys\.Modify|Permissions" <<<"$j"'

# --- Fichier d'accès sur adm01 ----------------------------------------------------------------------
check_cmd "fichier d'accès présent : $_M04O_ENV_PVE" test -s "$_M04O_ENV_PVE"
check_output "fichier d'accès en mode 600" '^600$' stat -c '%a' "$_M04O_ENV_PVE"
check_cmd "fichier d'accès : URL, utilisateur, jeton et secret renseignés" \
  bash -c 'for v in PROXMOX_URL PROXMOX_USER PROXMOX_TOKEN_ID PROXMOX_TOKEN_SECRET; do grep -Eq "^(export[[:space:]]+)?$v=\"?[^\"<]" "$1" || exit 1; done' \
  _ "$_M04O_ENV_PVE"

# --- Le fichier d'inventaire ---------------------------------------------------------------------------
check_cmd "inventories/lab/proxmox.yml publié sur main" _m04_fichier_main inventories/lab/proxmox.yml
check_cmd "proxmox.yml utilise le plugin community.proxmox.proxmox" \
  _m04_contient inventories/lab/proxmox.yml '^plugin:[[:space:]]*community\.proxmox\.proxmox[[:space:]]*$'
check_cmd "proxmox.yml ne contient aucun secret ni désactivation de TLS" \
  bash -c '! grep -Eiq "token_secret|password|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|validate_certs:[[:space:]]*(false|no)" "$1"' \
  _ "$_M04_SRC/inventories/lab/proxmox.yml"
check_cmd "ansible.cfg : l'inventaire par défaut est inventories/lab/proxmox.yml" \
  _m04_contient ansible.cfg '^[[:space:]]*inventory[[:space:]]*=[[:space:]]*inventories/lab/proxmox\.yml'
check_output "ansible.cfg : une source d'inventaire illisible est une erreur (unparsed_is_failed)" \
  'INVENTORY_UNPARSED_IS_FAILED.*True' _m04_ans ansible-config dump --only-changed

# --- L'inventaire produit ----------------------------------------------------------------------------------
_m04o_inv="$(_m04o_inventaire)"
check_cmd "ansible-inventory lit l'inventaire dynamique sans erreur" jq -e '._meta.hostvars | length > 0' <<<"$_m04o_inv"
for _m04o_h in $_M04_SOCLE; do
  check_cmd "groupe socle : $_m04o_h" _m04o_groupe_contient "$_m04o_inv" socle "$_m04o_h"
done
for _m04o_paire in role_routeur:gw01 role_bastion:adm01 role_dns:dns01 role_gitlab:git01 role_runner:runner01; do
  check_cmd "groupe ${_m04o_paire%%:*} : ${_m04o_paire#*:}" \
    _m04o_groupe_contient "$_m04o_inv" "${_m04o_paire%%:*}" "${_m04o_paire#*:}"
done
for _m04o_paire in gw01:10.10.10.1 adm01:10.10.10.10 dns01:10.10.20.10 git01:10.10.20.12 runner01:10.10.20.15; do
  check_output "ansible_host de ${_m04o_paire%%:*} = ${_m04o_paire#*:}" "^${_m04o_paire#*:}\$" \
    _m04o_hostvar "$_m04o_inv" "${_m04o_paire%%:*}" ansible_host
done
check_cmd "aucun template ni instance Molecule dans l'inventaire" \
  bash -c 'jq -e "._meta.hostvars | keys | map(select(test(\"^(tpl-|deb13-gold|rocky10-gold|m04-mol)\"))) | length == 0" <<<"$1" >/dev/null' \
  _ "$_m04o_inv"
check_output "dns01 : connexion par adresse IP (ansible ping par l'inventaire dynamique)" '"ping": *"pong"' \
  _m04_json ansible dns01 -m ansible.builtin.ping

# --- Registre des secrets ----------------------------------------------------------------------------------
check_cmd "registre des secrets : jeton wb-ansible@pve!ansible inscrit" \
  bash -c 'grep -q "wb-ansible@pve!ansible" "$1/docs/socle/registre-secrets.md"' _ "${WB_DEPOT:-$HOME/medisphere}"
