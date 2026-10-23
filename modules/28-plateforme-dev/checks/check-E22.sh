# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E22.sh — M28-E22 « Le portail ne crée plus de services » : ExternalSecret du portail synchronisé,
# svc-portail au moins Developer dans les groupes des équipes, modèle nouveau-service n'utilisant que des
# actions connues et l'hôte git01, aucun projet d'essai restant ; RB-288 ; panne close. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E22 — Le portail crée de nouveau des services"
require_cmd kubectl jq curl

_m28_e22_niveau_svc() {
  gitlab_api "groups/$1/members/all?query=svc-portail" 2>/dev/null |
    jq -e '[.[] | select(.username == "svc-portail") | .access_level] | (length >= 1 and min >= 30)' >/dev/null 2>&1
}
_m28_e22_pas_d_essai() {
  gitlab_api "projects?search=essai-inc5522&per_page=20" 2>/dev/null | jq -e 'length == 0' >/dev/null 2>&1
}
if _m28p_api_repond; then
  check_cmd "ExternalSecret portail synchronisé (Ready)" _m28p_kq \
    'any(.status.conditions[]?; .type == "Ready" and .status == "True")' -n portail externalsecrets.external-secrets.io portail
fi
check_cmd "svc-portail au moins Developer dans le groupe medidoc" _m28_e22_niveau_svc medidoc
check_cmd "svc-portail au moins Developer dans le groupe mediagenda" _m28_e22_niveau_svc mediagenda
check_cmd "modèle nouveau-service : actions connues seulement" _m28x_catalogue \
  'catalog/entities/by-name/template/default/nouveau-service' \
  '[.spec.steps[].action] | all(IN("fetch:template", "publish:gitlab", "publish:gitlab:merge-request", "catalog:register", "debug:log", "fetch:plain"))'
check_cmd "modèle nouveau-service : dépôts créés sur git01 uniquement" _m28x_catalogue \
  'catalog/entities/by-name/template/default/nouveau-service' \
  '[.spec.steps[].input.repoUrl? // empty | tostring] | all(startswith("git01.par1.medisphere.internal"))'
check_cmd "aucun projet d'essai (essai-inc5522) restant dans GitLab" _m28_e22_pas_d_essai
check_cmd "RB-288 publié (main) : messages et rotation du jeton" _m28p_doc RB-288 '401' '403' 'rotation'
check_cmd "panne M28-E22 close (lab/bin/break 28 22 --annuler après réparation)" _m28x_aucune_panne_active E22
