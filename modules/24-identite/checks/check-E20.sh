# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E20.sh — M24-E20 : SSH par certificats courts après SSO.
# Vérifie, en lecture seule depuis adm01 :
#   - le client Keycloak step-ca (flux standard, PKCE S256, seule URI http://127.0.0.1:10000) ;
#   - le provisioner OIDC « keycloak » publié par step-ca (client, émetteur, aucun administrateur,
#     16 h au plus, gabarit SSH qui fixe le principal à preferred_username) ;
#   - sur mon01 : sshd consulte une commande de principaux, qui répond pour une personne de l'annuaire
#     et pas pour admin ni root ; le journal montre une connexion par certificat sous ton nom et un
#     refus au compte (HBAC) pour julien.petit ;
#   - docs/socle/acces-ssh.md sur main.

# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

title "M24-E20 — SSH par certificats courts après SSO"
require_cmd jq curl

# --- 1. Le client Keycloak ------------------------------------------------------------------------
_m24c_e20_client="$(_m24c_kc_client step-ca)"
check_cmd "Client step-ca : flux standard seul (ni implicite, ni mot de passe), PKCE S256" _m24c_json "$_m24c_e20_client" \
  '.enabled and .standardFlowEnabled and (.implicitFlowEnabled | not) and (.directAccessGrantsEnabled | not)
   and .attributes["pkce.code.challenge.method"] == "S256"'
check_cmd "Client step-ca : une seule URI de retour, http://127.0.0.1:10000" _m24c_json "$_m24c_e20_client" \
  '.redirectUris == ["http://127.0.0.1:10000"]'

# --- 2. Le provisioner de step-ca ------------------------------------------------------------------
_m24c_e20_prov="$(_m24c_provisioners | jq -c '[.provisioners[]? | select(.type == "OIDC" and .name == "keycloak")][0] // empty' 2>/dev/null || true)"
check_cmd "step-ca : provisioner OIDC « keycloak », client step-ca, émetteur du royaume medisphere" _m24c_json "$_m24c_e20_prov" \
  '.clientID == "step-ca" and (.configurationEndpoint | startswith($e))' --arg e "$_M24C_EMETTEUR"
check_cmd "step-ca : provisioner « keycloak » sans administrateur (personne ne choisit ses principaux)" _m24c_json "$_m24c_e20_prov" \
  '(.admins // []) | length == 0'
check_cmd "step-ca : certificats SSH d'utilisateur de 16 h au plus, adresse d'écoute fixe 127.0.0.1:10000" _m24c_json "$_m24c_e20_prov" \
  '.claims.enableSSHCA == true and .listenAddress == "127.0.0.1:10000"
   and ((.claims.maxUserSSHCertDuration // "16h") | test("^(([0-9]|1[0-5])h([0-9]+m)?|16h|[0-9]+m)$"))'
check_cmd "step-ca : le gabarit SSH fixe le principal à preferred_username" _m24c_json "$_m24c_e20_prov" \
  '.options.ssh.template // "" | test("principals\"?\\s*:\\s*\\[\\s*\\{\\{\\s*toJson\\s+\\.Token\\.preferred_username")'

# --- 3. sshd sur mon01 ------------------------------------------------------------------------------
_m24c_e20_sshd="$(_m24c_ssh "$_M24C_MON01" 'sudo -n sshd -T 2>/dev/null | grep -E "^authorizedprincipals(command|commanduser|file) "')"
check_output "mon01 : sshd consulte une commande de principaux (AuthorizedPrincipalsCommand … %u)" \
  '^authorizedprincipalscommand /[^ ]+ %u$' printf '%s\n' "$_m24c_e20_sshd"
check_output "mon01 : la commande s'exécute sous un utilisateur sans droit (nobody)" \
  '^authorizedprincipalscommanduser nobody$' printf '%s\n' "$_m24c_e20_sshd"
_m24c_e20_cmd="$(sed -n 's/^authorizedprincipalscommand \(\/[^ ]*\) %u$/\1/p' <<<"$_m24c_e20_sshd")"
if [[ -z "$_m24c_e20_cmd" ]]; then
  skip "réponses de la commande de principaux" "commande introuvable dans sshd -T"
else
  check_ssh_output "mon01 : la commande accepte lucas.martin pour le compte lucas.martin (personne de l'annuaire)" \
    "$_M24C_MON01" '^lucas\.martin$' "$_m24c_e20_cmd lucas.martin"
  check_ssh_output "mon01 : la commande n'accepte AUCUN principal pour admin ni root (comptes locaux)" \
    "$_M24C_MON01" '^vide$' "out=\"\$($_m24c_e20_cmd admin)\$($_m24c_e20_cmd root)\"; [ -z \"\$out\" ] && echo vide"
fi

# --- 4. Les preuves dans le journal de mon01 ------------------------------------------------------------
if [[ -z "$_M24C_MOI" ]]; then
  skip "connexion par certificat sous ton nom" "WB_MOI non défini dans lab/lab.env"
else
  check_ssh "mon01 : une connexion par certificat sous ton nom ($_M24C_MOI) depuis 7 jours" "$_M24C_MON01" \
    "sudo -n journalctl -u ssh.service --since -7d -o cat | grep -Eq 'Accepted publickey for $_M24C_MOI from .*-CERT'"
fi
check_ssh "mon01 : julien.petit refusé à l'étape du compte (HBAC) depuis 7 jours" "$_M24C_MON01" \
  "sudo -n journalctl --since -7d -o cat | grep -Eq 'pam_sss\\(sshd:account\\).*julien\\.petit|Access denied for user julien\\.petit'"

# --- 5. La documentation -------------------------------------------------------------------------------
check_cmd "docs/socle/acces-ssh.md sur main de plateforme/medisphere (provisioner keycloak, bris de glace)" \
  _m24c_sur_main plateforme/medisphere docs/socle/acces-ssh.md 'keycloak'
