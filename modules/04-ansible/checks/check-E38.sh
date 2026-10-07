# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est un littéral (en-tête des fichiers chiffrés)
# check-E38.sh — M04-E38 « Panne : Decryption failed » : le coffre se déchiffre avec le secret
# prévu, le fichier de mot de passe est protégé et seul, le fichier chiffré est celui du dépôt.
# Lecture seule (ansible-vault view n'écrit rien).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E38 — Le coffre Ansible se déchiffre"
require_cmd git

# Fichier lu pour l'identité lab (script client de M04-E30 : ansible-vault-lab.pass d'abord).
_m04_e38_pass="$HOME/.config/workbook/ansible-vault.pass"
if [[ -e "$HOME/.config/workbook/ansible-vault-lab.pass" ]]; then
  _m04_e38_pass="$HOME/.config/workbook/ansible-vault-lab.pass"
fi

_m04_e38_view() { _m04x_ansible ansible-vault view "$_m04x_vault" >/dev/null 2>&1; }
_m04_e38_inventaire() { _m04x_ansible ansible-inventory --graph >/dev/null 2>&1; }
_m04_e38_mode() { [[ "$(stat -c %a "$_m04_e38_pass" 2>/dev/null)" == 600 && "$(stat -c %U "$_m04_e38_pass")" == "$(id -un)" ]]; }
_m04_e38_seul() { ! compgen -G "$HOME/.config/workbook/ansible-vault*.pass.*" >/dev/null; }
_m04_e38_depot() {
  git -C "$_m04x_src" ls-files --error-unmatch "$_m04x_vault" >/dev/null 2>&1 \
    && git -C "$_m04x_src" diff --quiet HEAD -- "$_m04x_vault" \
    && head -n 1 "$_m04x_src/$_m04x_vault" | grep -q '^\$ANSIBLE_VAULT;'
}
_m04_e38_identite() {
  local d
  d="$(_m04x_ansible ansible-config dump --only-changed 2>/dev/null)" || return 1
  grep -q '^DEFAULT_VAULT_IDENTITY_LIST(.*lab@' <<<"$d"
}

check_cmd "ansible-vault view $_m04x_vault réussit" _m04_e38_view
check_cmd "l'inventaire se charge (variables chiffrées comprises)" _m04_e38_inventaire
check_cmd "vault_identity_list déclare l'identité lab" _m04_e38_identite
check_cmd "fichier de mot de passe de l'identité lab (${_m04_e38_pass##*/}) en 600, à toi" _m04_e38_mode
check_cmd "aucun ancien fichier de mot de passe qui traîne (ansible-vault*.pass.*)" _m04_e38_seul
check_cmd "$_m04x_vault : chiffré, versionné, identique au dernier commit" _m04_e38_depot
check_cmd "panne M04-E38 close" _m04x_aucune_panne_active E38
