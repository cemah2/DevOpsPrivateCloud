# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées par bash -c
#
# check-E05.sh — M10-E05 : Keystone : domaines, projets, rôles
# À lancer depuis adm01. Lecture seule : CLI openstack (show, list, token issue) avec le cloud
# WB_OS_CLOUD et les clouds de E05, fichiers de ~/.config/openstack, copie de travail
# ~/src/openstack, API GitLab en GET. <MOI> vient de WB_MOI (lab/lab.env).

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E05 — Keystone : domaines, projets, rôles"
require_cmd jq openstack

_m10d_e05_moi="${WB_MOI:-}"

# --- 1. Domaine, projets, groupes, comptes ------------------------------------------------------
check_cmd "Domaine medisphere : existe et activé" \
  _m10d_jq "$(_m10d_os domain show medisphere)" '.enabled == true'
_m10d_e05_pr="$(_m10d_os project list --domain medisphere)"
check_cmd "Projets plateforme, mediagenda-dev, mediagenda-prod dans le domaine medisphere" _m10d_jq "$_m10d_e05_pr" \
  '[.[].Name] as $n | ["plateforme", "mediagenda-dev", "mediagenda-prod"] | all(. as $x | $n | index($x) != null)'
_m10d_e05_gr="$(_m10d_os group list --domain medisphere)"
check_cmd "Groupes equipe-plateforme et equipe-mediagenda dans le domaine medisphere" _m10d_jq "$_m10d_e05_gr" \
  '[.[].Name] as $n | ["equipe-plateforme", "equipe-mediagenda"] | all(. as $x | $n | index($x) != null)'
_m10d_e05_us="$(_m10d_os user list --domain medisphere)"
check_cmd "Comptes karim.benali et julien.petit dans le domaine medisphere" _m10d_jq "$_m10d_e05_us" \
  '[.[].Name] as $n | ["karim.benali", "julien.petit"] | all(. as $x | $n | index($x) != null)'
if [[ -n "$_m10d_e05_moi" ]]; then
  check_cmd "Compte $_m10d_e05_moi dans le domaine medisphere" _m10d_jq "$_m10d_e05_us" \
    "[.[].Name] | index(\"$_m10d_e05_moi\") != null"
else
  skip "Compte <MOI> dans le domaine medisphere" "WB_MOI vide dans lab/lab.env"
fi

# _m10d_e05_membre GROUPE UTILISATEUR — l'utilisateur est membre du groupe (domaine medisphere).
_m10d_e05_membre() {
  timeout 60 openstack --os-cloud "$_M10D_CLOUD" group contains user --group-domain medisphere \
    --user-domain medisphere "$1" "$2" 2>/dev/null | grep -q "^$2 in group"
}
check_cmd "julien.petit membre de equipe-mediagenda" _m10d_e05_membre equipe-mediagenda julien.petit
check_cmd "karim.benali membre de equipe-plateforme" _m10d_e05_membre equipe-plateforme karim.benali
if [[ -n "$_m10d_e05_moi" ]]; then
  check_cmd "$_m10d_e05_moi membre de equipe-plateforme" _m10d_e05_membre equipe-plateforme "$_m10d_e05_moi"
fi

# --- 2. Rôles : aux groupes, selon le tableau --------------------------------------------------
# _m10d_e05_role GROUPE ROLE PROJET — le groupe a ce rôle sur ce projet du domaine medisphere.
_m10d_e05_role() {
  _m10d_os role assignment list --names --group "$1" --group-domain medisphere \
    --project "$3" --project-domain medisphere \
    | jq -e --arg r "$2" 'map(select(.Role == $r)) | length == 1' >/dev/null 2>&1
}
check_cmd "equipe-plateforme : member sur plateforme" _m10d_e05_role equipe-plateforme member plateforme
check_cmd "equipe-plateforme : reader sur mediagenda-dev" _m10d_e05_role equipe-plateforme reader mediagenda-dev
check_cmd "equipe-plateforme : reader sur mediagenda-prod" _m10d_e05_role equipe-plateforme reader mediagenda-prod
check_cmd "equipe-mediagenda : member sur mediagenda-dev" _m10d_e05_role equipe-mediagenda member mediagenda-dev
check_cmd "equipe-mediagenda : reader sur mediagenda-prod" _m10d_e05_role equipe-mediagenda reader mediagenda-prod
check_cmd "equipe-mediagenda : AUCUN rôle sur plateforme" \
  bash -c 'timeout 60 openstack --os-cloud "$1" role assignment list --names --group equipe-mediagenda --group-domain medisphere --project plateforme --project-domain medisphere -f json 2>/dev/null | jq -e "length == 0" >/dev/null' _ "$_M10D_CLOUD"
# _m10d_e05_pas_direct PROJET — aucun rôle attribué directement à un utilisateur sur le projet.
_m10d_e05_pas_direct() {
  local j
  j="$(_m10d_os role assignment list --names --project "$1" --project-domain medisphere)"
  _m10d_jq "$j" 'map(select((.User // "") != "")) | length == 0'
}
for _m10d_e05_p in plateforme mediagenda-dev mediagenda-prod; do
  check_cmd "$_m10d_e05_p : aucun rôle attribué directement à une personne" _m10d_e05_pas_direct "$_m10d_e05_p"
done

# --- 3. Nettoyage de l'exploration ----------------------------------------------------------------
check_cmd "Domaine d'essai essai-e05 supprimé" bash -c 'timeout 60 openstack --os-cloud "$1" domain show medisphere >/dev/null 2>&1 && ! timeout 60 openstack --os-cloud "$1" domain show essai-e05 >/dev/null 2>&1' _ "$_M10D_CLOUD"
check_cmd "Application credential ac-essai-e05 supprimée" \
  bash -c 'j=$(timeout 60 openstack --os-cloud medisphere-plateforme application credential list -f json 2>/dev/null) && jq -e "map(select(.Name == \"ac-essai-e05\")) | length == 0" >/dev/null <<<"$j"'

# --- 4. Clients ----------------------------------------------------------------------------------
check_cmd "Cloud medisphere-plateforme : jeton obtenu" _m10d_os_ok --os-cloud medisphere-plateforme token issue
check_cmd "Cloud medisphere-mediagenda-dev : jeton obtenu" _m10d_os_ok --os-cloud medisphere-mediagenda-dev token issue
check_cmd "julien.petit ne peut pas obtenir de jeton pour le projet plateforme" \
  bash -c 'timeout 60 openstack --os-cloud medisphere-mediagenda-dev token issue >/dev/null 2>&1 && ! timeout 60 openstack --os-cloud medisphere-mediagenda-dev --os-project-name plateforme --os-project-domain-name medisphere token issue >/dev/null 2>&1'
check_cmd "adm01 : clouds.yaml sans mot de passe" \
  bash -c '[[ -s "$1" ]] && ! grep -Eiq "^[[:space:]]*password[[:space:]]*:" "$1"' _ "$HOME/.config/openstack/clouds.yaml"
check_cmd "adm01 : secure.yaml en 600" _m10d_mode "$HOME/.config/openstack/secure.yaml" 600

# --- 5. Le code ----------------------------------------------------------------------------------
check_cmd "plateforme/openstack (main) : playbooks/identite.yml" \
  _m10d_fichier_main plateforme/openstack playbooks/identite.yml
check_cmd "Mots de passe des comptes chiffrés sous l'identité « critique »" \
  bash -c 'for f in "$1"/donnees/vault-*.yml; do [[ -e "$f" ]] || exit 1; head -n 1 "$f" | grep -q "^\$ANSIBLE_VAULT;1\.2;AES256;critique" || exit 1; done' _ "$_M10D_OS"
