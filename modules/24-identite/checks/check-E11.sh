# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E11.sh — M24-E11 : SSO de GitLab
# À lancer depuis adm01. Lecture seule : client « gitlab » du royaume medisphere (wb-checks), page de
# connexion publique de GitLab, fichiers et pipelines de plateforme/identite et plateforme/ansible,
# membres directs des groupes GitLab (jeton read_api des checks).

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E11 — SSO de GitLab"
require_cmd jq curl

# _m24o_e11_niveau JSON IDENTIFIANT — niveau d'accès direct (0 si absent).
_m24o_e11_niveau() {
  jq -r --arg u "$2" '[.[] | select(.username == $u) | .access_level] | first // 0' <<<"$1" 2>/dev/null || echo 0
}

# _m24o_e11_planifie — statut du dernier pipeline planifié de main de plateforme/identite.
_m24o_e11_planifie() {
  gitlab_api "projects/plateforme%2Fidentite/pipelines?source=schedule&ref=main&per_page=1" 2>/dev/null \
    | jq -r '.[0].status // empty' 2>/dev/null || true
}

# --- 1. Le client et son secret --------------------------------------------------------------------
_m24o_controler_client gitlab confidentiel S256 \
  "https://git01.par1.medisphere.internal/users/auth/openid_connect/callback"
check_cmd "plateforme/identite : tofu/clients-gitlab.tf sur main (client en code, pas à la main)" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" tofu/clients-gitlab.tf 'client_id *= *"gitlab"'
check_cmd "plateforme/identite : outils/ranger-secret-client.sh sur main" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" outils/ranger-secret-client.sh 'keycloak_secrets_clients'
check_cmd "plateforme/ansible : secrets/identite.yml sur main, chiffré sous l'identité « critique »" \
  _m24o_vault_critique "$_M24O_P_ANSIBLE" secrets/identite.yml

# --- 2. GitLab ---------------------------------------------------------------------------------------
check_output "GitLab : la page de connexion propose le fournisseur openid_connect (bouton du SSO)" \
  '/users/auth/openid_connect' curl -sf --max-time "$WB_TIMEOUT" \
  "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/users/sign_in"

# --- 3. La synchronisation des groupes ---------------------------------------------------------------
check_cmd "plateforme/identite : outils/synchro-gitlab.py et sa table synchro-gitlab.yml sur main" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" outils/synchro-gitlab.yml 'synchro_gitlab:'
check_cmd "plateforme/identite : le script de synchronisation est sur main" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" outils/synchro-gitlab.py 'def main'
check_output "plateforme/identite : le dernier pipeline PLANIFIÉ de main a réussi (synchronisation horaire)" '^success$' \
  _m24o_e11_planifie

_m24o_e11_plateforme="$(_m24o_membres_gitlab plateforme)"
_m24o_e11_mediagenda="$(_m24o_membres_gitlab mediagenda)"
if [[ -z "$_m24o_e11_plateforme" || -z "$_m24o_e11_mediagenda" ]]; then
  _ko "GitLab : membres des groupes plateforme et mediagenda illisibles avec le jeton des checks"
else
  check_output "GitLab : lucas.martin est Developer (30) du groupe plateforme, pas plus" '^30$' \
    _m24o_e11_niveau "$_m24o_e11_plateforme" lucas.martin
  check_output "GitLab : karim.benali (plateforme-admins) est au moins Maintainer du groupe plateforme" '^(40|50)$' \
    _m24o_e11_niveau "$_m24o_e11_plateforme" karim.benali
  check_output "GitLab : julien.petit n'est pas membre direct du groupe plateforme" '^0$' \
    _m24o_e11_niveau "$_m24o_e11_plateforme" julien.petit
  check_output "GitLab : lucas.martin n'est pas membre direct du groupe mediagenda" '^0$' \
    _m24o_e11_niveau "$_m24o_e11_mediagenda" lucas.martin
  check_output "GitLab : julien.petit (mediagenda) est au moins Maintainer du groupe mediagenda" '^(40|50)$' \
    _m24o_e11_niveau "$_m24o_e11_mediagenda" julien.petit
fi
