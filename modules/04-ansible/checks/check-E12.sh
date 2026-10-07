# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E12.sh — M04-E12 : Ansible Vault
# À lancer depuis adm01. Lecture seule : fichiers et historique Git du projet, déchiffrement
# en mémoire (le contenu n'est jamais affiché), comptes et sshd sur les hôtes.

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E12 — Ansible Vault"
require_cmd git jq curl stat

# --- Le mot de passe du Vault ------------------------------------------------------------------
check_cmd "mot de passe Vault présent : $_M04O_PASS" test -s "$_M04O_PASS"
check_output "mot de passe Vault en mode 600" '^600$' stat -c '%a' "$_M04O_PASS"
check_output "dossier ~/.config/workbook en mode 700" '^700$' stat -c '%a' "$HOME/.config/workbook"
check_cmd "le mot de passe n'est pas suivi par Git dans le projet" \
  bash -c '! git -C "$1" ls-files | grep -Eiq "vault[-_.]?pass|\.pass$"' _ "$_M04_SRC"
check_cmd "ansible.cfg déclare l'identité « lab » et son fichier (vault_identity_list)" \
  _m04_contient ansible.cfg '^[[:space:]]*vault_identity_list[[:space:]]*=[[:space:]]*lab@'

# --- Le fichier chiffré -------------------------------------------------------------------------
check_cmd "$_M04O_VAULT présent" test -s "$_M04_SRC/$_M04O_VAULT"
check_output "$_M04O_VAULT chiffré avec l'identité « lab »" '^\$ANSIBLE_VAULT;1\.2;AES256;lab$' \
  head -n 1 "$_M04_SRC/$_M04O_VAULT"
check_cmd "toutes les versions commitées de vault.yml sont chiffrées" _m04o_vault_chiffre_partout
check_cmd "vault.yml publié sur main" _m04_fichier_main "$_M04O_VAULT"
check_cmd "vault.yml se déchiffre avec la configuration du projet" _m04o_vault_contient '.'
check_cmd "vault.yml contient vault_secours_mdp_hash (une empreinte, pas un mot de passe)" \
  _m04o_vault_contient '^vault_secours_mdp_hash:[[:space:]]*"?\$(y|6|5|2b|gy|7)\$'
check_cmd "vault_secours_mdp_hash est référencée en clair dans group_vars/all/main.yml" \
  _m04_contient inventories/lab/group_vars/all/main.yml 'vault_secours_mdp_hash'
check_cmd "aucune variable vault_* définie en dehors de vault.yml" \
  bash -c '! grep -rEq --exclude=vault.yml "^[[:space:]]*vault_[a-z0-9_]+:" "$1/inventories" "$1/playbooks" "$1/roles"' \
  _ "$_M04_SRC"
check_cmd "le compte de secours est géré sans afficher son empreinte (no_log)" \
  bash -c 'grep -rEq "no_log:[[:space:]]*true" "$1/roles/base/tasks"' _ "$_M04_SRC"

# --- Le résultat sur les hôtes ---------------------------------------------------------------------
for _m04o_h in $_M04_SOCLE; do
  check_ssh "$_m04o_h : compte secours présent, avec un mot de passe" "$_m04o_h" \
    'getent passwd secours >/dev/null && sudo -n passwd -S secours | awk "{exit !(\$2 == \"P\")}"'
  check_ssh "$_m04o_h : secours membre du groupe sudo" "$_m04o_h" 'id -nG secours | grep -qw sudo'
  check_ssh "$_m04o_h : sshd refuse le compte secours (DenyUsers)" "$_m04o_h" \
    'sudo -n sshd -T | grep -Eqi "^denyusers .*\bsecours\b"'
done

# --- Registre des secrets (plateforme/medisphere) ------------------------------------------------
check_cmd "registre des secrets : mot de passe Vault et compte secours inscrits" \
  bash -c 'f="$1/docs/socle/registre-secrets.md"; grep -q "ansible-vault.pass" "$f" && grep -qi "secours" "$f"' \
  _ "${WB_DEPOT:-$HOME/medisphere}"
