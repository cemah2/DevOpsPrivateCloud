# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes (évaluées sur l'hôte distant)
#
# check-E15.sh — M24-E15 : Proxmox VE, PBS et NetBox en SSO
# À lancer depuis adm01. Lecture seule : clients « proxmox », « pbs », « netbox » (wb-checks) ;
# SSH root@pve01 et root@pbs01 (pveum, pvesh, proxmox-backup-manager en lecture) ; page de connexion
# publique de NetBox et grep en sudo -n sur nbx01 (aucune valeur affichée).

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E15 — Proxmox VE, PBS et NetBox en SSO"
require_cmd jq curl ssh

# --- 1. Les clients -----------------------------------------------------------------------------------------
_m24o_controler_client proxmox confidentiel S256 "https://pve01.par1.medisphere.internal:8006"
_m24o_controler_client pbs confidentiel S256 "https://pbs01.par2.medisphere.internal:8007"
_m24o_controler_client netbox confidentiel S256 "https://nbx01.par1.medisphere.internal/oauth/complete/oidc/"

# --- 2. Proxmox VE (pve01) ---------------------------------------------------------------------------------
_m24o_e15_royaume="$(_m24d_ssh "$WB_PVE_HOST" 'pvesh get /access/domains/medisphere --output-format json')"
check_cmd "pve01 : royaume medisphere de type openid, émetteur du royaume, client proxmox" \
  _m24o_json "$_m24o_e15_royaume" --arg e "$_M24D_EMETTEUR" '.type == "openid" and ."issuer-url" == $e and ."client-id" == "proxmox"'
check_cmd "pve01 : identifiant = preferred_username (username), groupes lus dans « groups », écrasés à chaque connexion" \
  _m24o_json "$_m24o_e15_royaume" '."username-claim" == "username" and ."groups-claim" == "groups"
    and ((."groups-overwrite" // 0) | tostring | test("^(1|true)$"))'
_m24o_e15_acl="$(_m24d_ssh "$WB_PVE_HOST" 'pveum acl list --output-format json')"
check_cmd "pve01 : PVEAdmin sur / pour le groupe plateforme-admins-medisphere" \
  _m24o_json "$_m24o_e15_acl" 'any(.[]; .ugid == "plateforme-admins-medisphere" and .type == "group" and .path == "/" and .roleid == "PVEAdmin")'
check_cmd "pve01 : PVEAuditor sur /pool/lab pour le groupe support-medisphere, et rien de plus large" \
  _m24o_json "$_m24o_e15_acl" '([.[] | select(.ugid == "support-medisphere")] | length >= 1)
    and all(.[] | select(.ugid == "support-medisphere"); .path == "/pool/lab" and .roleid == "PVEAuditor")'
check_cmd "pve01 : aucun droit donné directement à une personne du royaume medisphere (les droits passent par les groupes)" \
  _m24o_json "$_m24o_e15_acl" 'all(.[]; (.type == "user" and (.ugid | endswith("@medisphere"))) | not)'
_m24o_e15_utilisateurs="$(_m24d_ssh "$WB_PVE_HOST" 'pveum user list --output-format json')"
check_cmd "pve01 : wb-admin@pve est désactivé (root@pam reste le bris de glace)" \
  _m24o_json "$_m24o_e15_utilisateurs" 'any(.[]; .userid == "wb-admin@pve" and ((.enable // 1) | tostring) == "0")'
check_cmd "pve01 : aucun jeton de root@pam ne traîne (jeton temporaire de l'apply supprimé)" \
  _m24o_json "$(_m24d_ssh "$WB_PVE_HOST" 'pveum user token list root@pam --output-format json')" 'length == 0'

# --- 3. PBS (pbs01) ------------------------------------------------------------------------------------------
check_cmd "pbs01 : royaume OpenID medisphere (client pbs, émetteur du royaume)" \
  _m24o_json "$(_m24d_ssh "$WB_PBS_HOST" 'proxmox-backup-manager openid list --output-format json')" \
  --arg e "$_M24D_EMETTEUR" 'any(.[]; .realm == "medisphere" and ."client-id" == "pbs" and ."issuer-url" == $e)'
check_cmd "pbs01 : aucun jeton de root@pam ne traîne (jeton temporaire supprimé)" \
  _m24o_json "$(_m24d_ssh "$WB_PBS_HOST" 'proxmox-backup-manager user list-tokens root@pam --output-format json')" 'length == 0'

# --- 4. NetBox (nbx01) ----------------------------------------------------------------------------------------
check_output "NetBox : la page de connexion propose le SSO (backend oidc)" '/oauth/login/oidc/' \
  curl -sf --max-time "$WB_TIMEOUT" "${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}/login/"
check_ssh "nbx01 : configuration.py déclare le backend OIDC avec PKCE (sans afficher le fichier)" "$_M24O_NBX01" \
  'sudo -n grep -q "social_core.backends.open_id_connect.OpenIdConnectAuth" /opt/netbox/netbox/netbox/configuration.py \
   && sudo -n grep -Eq "^SOCIAL_AUTH_OIDC_USE_PKCE *= *True" /opt/netbox/netbox/netbox/configuration.py'
check_ssh "nbx01 : NetBox utilise le magasin du système pour joindre Keycloak (REQUESTS_CA_BUNDLE)" "$_M24O_NBX01" \
  'systemctl show netbox -p Environment | grep -q "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"'
