# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E27.sh — M05-E27 « Secrets et chiffrement de l'état »
# Objets d'état chiffrés dans tofu-state, bloc encryption définitif (enforced, sans fallback en
# clair) sur main pour chaque configuration et pour Terragrunt, phrase hors du dépôt (fichier 600,
# variable CI protégée et masquée, registre des secrets), plan du socle vide, VMs 2057-2058
# détruites.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E27 — Chiffrement de l'état"
require_cmd jq aws curl ssh tofu
_m05p_charger

title "États chiffrés (tofu-state)"
for _m05_e27_c in socle envs/lab-m05 envs/recette-m05; do
  check_cmd "$_m05_e27_c : objet d'état chiffré (aucune ressource lisible)" \
    _m05p_objet_chiffre "$_m05_e27_c/terraform.tfstate"
done
# _m05_e27_tg_chiffres — les états Terragrunt encore présents sont chiffrés (au moins un existe).
_m05_e27_tg_chiffres() {
  local cles c n=0
  cles="$(_m05p_aws s3api list-objects-v2 --bucket "$_M05P_BUCKET" --prefix envs/ 2>/dev/null \
    | jq -r '(.Contents // [])[].Key | select(test("^envs/[^/]+/[^/]+/terraform\\.tfstate$"))' 2>/dev/null)" || return 1
  for c in $cles; do
    _m05p_objet_chiffre "$c" || return 1
    n=$((n + 1))
  done
  [[ $n -gt 0 ]]
}
check_cmd "unités Terragrunt (envs/<env>/<unité>) : tous les états chiffrés" _m05_e27_tg_chiffres

title "Code (branche main)"
for _m05_e27_c in socle envs/lab-m05 envs/recette-m05; do
  check_cmd "$_m05_e27_c/chiffrement.tf : state et plan chiffrés, enforced" \
    _m05p_main_contient "$_m05_e27_c/chiffrement.tf" 'method[[:space:]]+"aes_gcm"' 'enforced[[:space:]]*=[[:space:]]*true' '^[[:space:]]*plan[[:space:]]*\{'
  check_cmd "$_m05_e27_c/chiffrement.tf : plus de méthode unencrypted (migration terminée)" \
    _m05p_main_sans "$_m05_e27_c/chiffrement.tf" 'unencrypted'
  check_cmd "$_m05_e27_c/chiffrement.tf : aucune phrase dans le code" \
    _m05p_main_sans "$_m05_e27_c/chiffrement.tf" 'passphrase[[:space:]]*='
done
check_cmd "terragrunt/live/root.hcl : bloc encryption généré pour toutes les unités" \
  _m05p_main_contient terragrunt/live/root.hcl 'generate[[:space:]]+"[^"]*chiffr|encryption'
check_cmd "outils/charger-acces.sh présent" _m05p_fichier_main outils/charger-acces.sh
# _m05_e27_phrase_hors_depot — la phrase de adm01 n'apparaît dans aucun commit du clone local.
_m05_e27_phrase_hors_depot() {
  local p
  p="$(tr -d '\n' < "$_M05P_CFG/tofu-chiffrement.pass" 2>/dev/null)" || return 1
  [[ ${#p} -ge 16 ]] || return 1
  # Recherche « pickaxe » sur tout l'historique : un commit qui a ajouté la phrase est trouvé.
  git -C "$_M05P_INFRA" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [[ -z "$(git -C "$_M05P_INFRA" log --all --format=%H -S"$p" 2>/dev/null | head -n 1)" ]]
}

title "Phrase de chiffrement"
# shellcheck disable=SC2088  # tilde affiché littéralement dans le libellé
check_cmd "~/.config/workbook/tofu-chiffrement.pass en 600" _m05p_droits "$_M05P_CFG/tofu-chiffrement.pass" 600
check_cmd "la phrase fait au moins 32 caractères" \
  bash -c '[ "$(tr -d "\n" < "$1" | wc -c)" -ge 32 ]' _ "$_M05P_CFG/tofu-chiffrement.pass"
check_cmd "la phrase n'apparaît dans aucun commit de plateforme/infra" _m05_e27_phrase_hors_depot
check_cmd "TOFU_PHRASE_CHIFFREMENT : protégée et masquée" \
  _m05p_variable_ok TOFU_PHRASE_CHIFFREMENT '.protected and (.masked or (.masked_and_hidden // false))'
check_cmd "registre des secrets : phrase de chiffrement inscrite" \
  _m05p_doc_contient "$_M05P_DOC/registre-secrets.md" 'tofu-chiffrement' 'rotation'

title "Résultat"
check_cmd "socle : « tofu plan » ne propose aucun changement" _m05p_plan_vide "$_M05P_INFRA/socle"
check_cmd "dev-agenda détruit (VMs 2057 et 2058 absentes)" _m05p_aucune_vm 2057 2058
