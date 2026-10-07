# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E29.sh — M05-E29 « Sauvegarder et restaurer l'état »
# Sauvegarde planifiée (PLANIF=sauvegarde-etats) réussie, artefact conservé ~90 jours, scripts
# sur main, restauration d'envs/lab-m05 faite (plan vide, versions), _restauration/ vidé, aucune
# copie d'état dans le clone, tableau des scénarios avec un RTO mesuré dans docs/socle/iac.md.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E29 — Sauvegarde et restauration de l'état"
require_cmd jq aws curl tofu

# _m05_e29_sauvegarde_ok — le dernier job sauvegarde-etats planifié a réussi et garde ses
#   artefacts au moins 80 jours.
_m05_e29_sauvegarde_ok() {
  local j
  j="$(_m05p_dernier_job_planifie '^sauvegarde-etats$')" || return 1
  jq -e '.status == "success"' >/dev/null <<<"$j" && _m05p_artefacts_conserves "$j" 80
}

# _m05_e29_versions_lab — l'état d'envs/lab-m05 porte la trace d'une restauration par copie d'une
#   version : deux versions de même ETag (la copie côté serveur d'une version garde son contenu,
#   donc son empreinte ; deux écritures d'OpenTofu, elles, diffèrent toujours par leur serial).
#   Le simple nombre de versions ne prouverait rien : l'état en a déjà beaucoup depuis le palier 2.
_m05_e29_versions_lab() {
  _m05p_aws s3api list-object-versions --bucket "$_M05P_BUCKET" --prefix envs/lab-m05/terraform.tfstate 2>/dev/null \
    | jq -e '[(.Versions // [])[] | select(.Key == "envs/lab-m05/terraform.tfstate") | .ETag]
             | (length > (unique | length))' >/dev/null 2>&1
}

# _m05_e29_pas_de_copie — aucun fichier d'état ni de sauvegarde d'état dans ~/src/infra.
_m05_e29_pas_de_copie() {
  [[ -d "$_M05P_INFRA" ]] || return 1
  [[ -z "$(find "$_M05P_INFRA" \( -name .terraform -o -name .git -o -name .terragrunt-cache \) -prune \
           -o -type f \( -name '*.tfstate' -o -name '*.tfstate.*' -o -name 'manifeste.json' \) -print 2>/dev/null)" ]]
}

title "Sauvegarde planifiée (GitLab)"
check_cmd "pipeline planifié actif sur main avec PLANIF=sauvegarde-etats" _m05p_planif sauvegarde-etats
check_cmd "le dernier job sauvegarde-etats a réussi et garde ses artefacts ~90 jours" _m05_e29_sauvegarde_ok
check_cmd "artefacts de sauvegarde réservés (access: maintainer ou none)" \
  _m05p_main_contient .gitlab-ci.yml '^sauvegarde-etats:' 'access:[[:space:]]*"?(maintainer|none)'
check_cmd "outils/sauvegarder-etats.sh présent sur main" _m05p_fichier_main outils/sauvegarder-etats.sh
check_cmd "outils/restaurer-etat.sh présent sur main" _m05p_fichier_main outils/restaurer-etat.sh
check_cmd "sauvegarder-etats.sh ne déchiffre rien (pas de « state pull »)" \
  _m05p_main_sans outils/sauvegarder-etats.sh 'state[[:space:]]+pull'

title "Restaurations"
check_cmd "envs/lab-m05 : une version précédente a été restaurée (copie d'une version dans l'historique)" _m05_e29_versions_lab
check_cmd "envs/lab-m05 : « tofu plan » ne propose aucun changement" _m05p_plan_vide "$_M05P_INFRA/envs/lab-m05"
check_cmd "aucun objet laissé sous _restauration/" _m05p_aucune_cle_prefixe _restauration/
check_cmd "aucune copie d'état dans ~/src/infra" _m05_e29_pas_de_copie

title "Documentation"
check_cmd "docs/socle/iac.md : scénarios, RPO, RTO et la phrase de chiffrement perdue" \
  _m05p_doc_contient "$_M05P_DOC/iac.md" 'restaur' 'RPO' 'RTO' 'phrase'
check_cmd "docs/socle/iac.md : un RTO mesuré (en minutes)" \
  _m05p_doc_contient "$_M05P_DOC/iac.md" 'mesur[^|]*[0-9]+[[:space:]]*min'
