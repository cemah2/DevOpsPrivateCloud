# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E30.sh — M04-E30 « Vault en production : séparation et rotation »
# Deux identités Vault déclarées par le script client avec vault_id_match, fichiers chiffrés
# sous chaque identité, mots de passe distincts en 600, variable CI critique protégée et de
# portée lab/socle, script client qui échoue proprement, outils et runbook présents.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E30 — Vault en production"
require_cmd jq curl git

title "Configuration (branche main)"
check_cmd "ansible.cfg : identité lab par le script client" \
  _m04_fichier_main_contient ansible.cfg '^[[:space:]]*vault_identity_list[[:space:]]*=.*lab@[^,]*vault-pass-client'
check_cmd "ansible.cfg : identité critique par le script client" \
  _m04_fichier_main_contient ansible.cfg '^[[:space:]]*vault_identity_list[[:space:]]*=.*critique@[^,]*vault-pass-client'
check_cmd "ansible.cfg : vault_id_match activé" \
  _m04_fichier_main_contient ansible.cfg '^[[:space:]]*vault_id_match[[:space:]]*=[[:space:]]*([Tt]rue|yes|1)'
check_cmd "outils/vault-pass-client.sh présent sur main" _m04_fichier_main outils/vault-pass-client.sh
check_cmd "outils/secrets-dans-journal.py présent sur main" _m04_fichier_main outils/secrets-dans-journal.py
check_cmd ".gitlab-ci.yml : journaux vérifiés avant publication" \
  _m04_fichier_main_contient .gitlab-ci.yml 'secrets-dans-journal|publier-journal'

title "Fichiers chiffrés (clone local, fichiers suivis par git)"
if [[ -d "$_M04_SRC/.git" ]]; then
  check_cmd "au moins un fichier chiffré sous l'identité lab" \
    bash -c 'cd "$1" && git ls-files -z | xargs -0 grep -l "^\$ANSIBLE_VAULT;1\.2;AES256;lab$" 2>/dev/null | grep -q .' _ "$_M04_SRC"
  check_cmd "au moins un fichier chiffré sous l'identité critique" \
    bash -c 'cd "$1" && git ls-files -z | xargs -0 grep -l "^\$ANSIBLE_VAULT;1\.2;AES256;critique$" 2>/dev/null | grep -q .' _ "$_M04_SRC"
  check_cmd "script client exécutable" test -x "$_M04_SRC/outils/vault-pass-client.sh"
  check_cmd "script client : échec propre sans mot de passe (code 1, rien sur la sortie standard)" \
    bash -c 'out="$(env -i PATH=/usr/bin:/bin HOME=/nonexistent "$1/outils/vault-pass-client.sh" --vault-id critique 2>/dev/null)"; rc=$?; [ "$rc" -eq 1 ] && [ -z "$out" ]' _ "$_M04_SRC"
else
  skip "fichiers chiffrés et script client" "pas de clone dans $_M04_SRC"
fi

title "Mots de passe sur adm01"
_m04_vp="$HOME/.config/workbook"
check_output "mot de passe critique en 600" '^600$' stat -c '%a' "$_m04_vp/ansible-vault-critique.pass"
check_cmd "mots de passe lab et critique différents" \
  bash -c '[ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"' _ "$_m04_vp/ansible-vault.pass" "$_m04_vp/ansible-vault-critique.pass"

title "GitLab"
check_cmd "VAULT_PASS_CRITIQUE : fichier, protégée, portée lab/socle" \
  _m04_variable_ok VAULT_PASS_CRITIQUE '.protected and .variable_type == "file" and .environment_scope == "lab/socle"'
_m04_e30_pas_globale() {
  _m04_api_ok "$_M04_PROJET/variables?per_page=100" 'type == "array"' \
    && ! _m04_variable_ok VAULT_PASS_CRITIQUE '.environment_scope == "*"'
}
check_cmd "aucune VAULT_PASS_CRITIQUE de portée « toutes » (*)" _m04_e30_pas_globale

title "Documentation"
check_cmd "RB-041 (rotation des secrets Vault) dans docs/socle/runbooks/" \
  bash -c 'ls "$1"/runbooks/RB-041*.md >/dev/null 2>&1' _ "$_M04_DOC"
check_cmd "registre des secrets : identités lab et critique" \
  _m04_doc_contient "$_M04_DOC/registre-secrets.md" 'critique' 'rotation'
