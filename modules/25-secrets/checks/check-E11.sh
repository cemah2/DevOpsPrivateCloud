# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M25-E11 « Ansible lit ses secrets dans OpenBao ».
# Vérifie : deux secrets KV distincts pour les identités lab et critique (métadonnées), politiques
# ansible-lab / ansible-critique séparées, rôles JWT du pipeline de plateforme/ansible, script client
# réécrit sur main, lookup community.hashi_vault pour Mailpit, pipeline vert, plus de variable
# VAULT_PASS_* ni de fichier ansible-vault*.pass sur adm01, procédure de bris de glace écrite.
# Lecture seule : bao_api (wb-checks), gitlab_api, fichiers de adm01 (ls seulement, jamais lus).

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E11 — Ansible lit ses secrets dans OpenBao"
require_cmd jq curl

# --- Coffre ----------------------------------------------------------------------------------------
check_cmd "kv/plateforme/ansible-vault/lab existe" _m25o_kv_existe plateforme/ansible-vault/lab
check_cmd "kv/plateforme/ansible-vault/critique existe (chemin distinct : les politiques protègent des chemins)" \
  _m25o_kv_existe plateforme/ansible-vault/critique
check_cmd "politique ansible-lab : lit l'identité lab" _m25o_politique_contient ansible-lab 'kv/data/plateforme/ansible-vault/lab'
check_cmd "politique ansible-lab : aucun accès à critique ni joker sur ansible-vault" \
  _m25o_politique_exclut ansible-lab 'critique|ansible-vault/\*|ansible-vault/\+'
check_cmd "politique ansible-critique : lit l'identité critique et les comptes de Mailpit" \
  bash -c 'grep -q "kv/data/plateforme/ansible-vault/critique" <<<"$1" && grep -q "kv/data/plateforme/mailpit/" <<<"$1"' _ \
  "$(_m25o_politique ansible-critique)"
check_cmd "kv/plateforme/mailpit/comptes existe" _m25o_kv_existe plateforme/mailpit/comptes

_m25o_e11_id="$(_m25o_projet_id "$_M25O_P_ANSIBLE")"
check_cmd "rôle ci-plateforme-ansible : project_id de plateforme/ansible, références protégées, politique ansible-lab" \
  _m25o_json "$(_m25o_bao auth/gitlab/role/ci-plateforme-ansible)" --arg id "${_m25o_e11_id:-x}" '
  ([.data.bound_claims.project_id] | flatten | map(tostring) == [$id])
  and ([.data.bound_claims.ref_protected] | flatten == ["true"])
  and (.data.token_policies | index("ansible-lab")) != null
  and (.data.token_policies | index("ansible-critique")) == null'
check_cmd "rôle ci-plateforme-ansible-critique : main et environnement lab/socle seulement" \
  _m25o_json "$(_m25o_bao auth/gitlab/role/ci-plateforme-ansible-critique)" '
  ([.data.bound_claims.ref] | flatten == ["main"])
  and ([.data.bound_claims.environment] | flatten == ["lab/socle"])
  and (.data.token_policies | index("ansible-critique")) != null'

# --- Dépôt plateforme/ansible ----------------------------------------------------------------------
check_cmd "outils/vault-pass-client.sh (main) lit le coffre (bao kv get)" \
  _m25o_contient "$_M25O_P_ANSIBLE" outils/vault-pass-client.sh 'bao kv get'
check_cmd "outils/vault-pass-client.sh : les anciennes sources seulement en mode secours explicite" \
  _m25o_contient "$_M25O_P_ANSIBLE" outils/vault-pass-client.sh 'VAULT_PASS_SECOURS'
check_cmd "collections/requirements.yml : community.hashi_vault" \
  _m25o_contient "$_M25O_P_ANSIBLE" collections/requirements.yml 'community\.hashi_vault'
check_cmd "host_vars/mon01/mailpit.yml : mots de passe lus par vault_kv2_get" \
  _m25o_contient "$_M25O_P_ANSIBLE" inventories/lab/host_vars/mon01/mailpit.yml 'community\.hashi_vault\.vault_kv2_get'
check_cmd ".gitlab-ci.yml : jetons d'identité et rôles ci-plateforme-ansible*" \
  bash -c 'c="$1"; [[ -n "$c" ]] && grep -q "id_tokens:" <<<"$c" && grep -q "ci-plateforme-ansible-critique" <<<"$c"' _ \
  "$(_m25o_contenu "$_M25O_P_ANSIBLE" .gitlab-ci.yml)"
check_cmd "plateforme/ansible : dernier pipeline de main réussi" _m25o_pipeline_vert "$_M25O_P_ANSIBLE"

_m25o_e11_vars="" _m25o_e11_rc=0
_m25o_e11_vars="$(_m25o_variables projects "$_M25O_P_ANSIBLE")" || _m25o_e11_rc=$?
if ((_m25o_e11_rc == 2)); then
  skip "variables de CI de plateforme/ansible" "le jeton des checks n'a pas le droit de les lister"
else
  check_cmd "variables de CI de plateforme/ansible : plus de VAULT_PASS_LAB ni VAULT_PASS_CRITIQUE" \
    bash -c '! grep -Eq "^VAULT_PASS_(LAB|CRITIQUE)$" <<<"$1"' _ "$_m25o_e11_vars"
fi

# --- adm01 : plus de mot de passe en fichier (on ne lit PAS les fichiers, on constate leur absence) --
_m25o_e11_sans_fichier() {
  local f
  for f in "$HOME"/.config/workbook/ansible-vault*.pass; do
    [[ -e "$f" ]] && return 1
  done
  return 0
}
check_cmd "adm01 : plus aucun ~/.config/workbook/ansible-vault*.pass" _m25o_e11_sans_fichier
check_cmd "adm01 : client bao installé" command -v bao

# --- Bris de glace ---------------------------------------------------------------------------------
_m25o_e11_bris_de_glace() {
  local c
  c="$(_m25o_contenu "$_M25O_P_DOC" "$_M25O_DOC_SECRETS/ansible-et-openbao.md")"
  [[ -n "$c" ]] && grep -Eqi 'bris de glace' <<<"$c" && grep -Eqi 'essai.*[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$c"
}
check_cmd "docs/securite/secrets/ansible-et-openbao.md : procédure de bris de glace, avec la date de son essai" \
  _m25o_e11_bris_de_glace
