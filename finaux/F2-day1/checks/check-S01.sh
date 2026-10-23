# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts bash -c entre apostrophes (arguments positionnels)
#
# check-S01.sh — F2-S01 : l'offre de service de la plateforme (RED, livrable publié)
# À lancer depuis adm01. Lecture seule : fichiers de plateforme/medisphere sur main (GitLab, jeton des
# checks). Présence et contenu minimal seulement (CONVENTIONS §7) ; le fond s'auto-évalue avec le corrigé.

# shellcheck source=_f2-cadre.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-cadre.sh"

title "F2-S01 — L'offre de service de la plateforme"
require_cmd jq curl

_f2a_s01_offre="$(_f2a_fichier "$_F2A_P_DOC" "$_F2A_DOC/offre-de-service.md")"
check_cmd "$_F2A_DOC/offre-de-service.md publié sur main" bash -c '[[ -n "$1" ]]' _ "$_f2a_s01_offre"

check_cmd "offre : ce que la plateforme fournit ET ce qu'elle ne fournit pas" \
  _f2a_contient "$_f2a_s01_offre" "fourni" "ne (fournit|fournissons|propose) pas|hors (du )?périmètre|non fourni"
check_cmd "offre : responsabilités partagées (plateforme / équipe)" \
  _f2a_contient "$_f2a_s01_offre" "responsabilit" "plateforme" "(e|é|É)quipe"
check_cmd "offre : niveaux de service chiffrés (au moins un objectif en %)" \
  _f2a_contient "$_f2a_s01_offre" "niveau(x)? de service|SLO|objectif" "[0-9]{2}([.,][0-9]+)? ?%"
check_cmd "offre : canaux de support (adresse ou ticket) et délais" \
  _f2a_contient "$_f2a_s01_offre" "support|contact|assistance" "@medisphere\.internal|DEV-|ticket" "délai|prise en charge|[0-9]+ ?(h|min|jour)"
check_cmd "offre : quotas par défaut (CPU et mémoire)" \
  _f2a_contient "$_f2a_s01_offre" "quota" "cpu" "m(e|é)moire|Gi|Mi"
check_cmd "offre : chemin balisé et exceptions" \
  _f2a_contient "$_f2a_s01_offre" "chemin balisé|golden path" "exception"

_f2a_s01_parcours="$(_f2a_fichier "$_F2A_P_DOC" "$_F2A_DOC/parcours-accueil.md")"
check_cmd "$_F2A_DOC/parcours-accueil.md publié sur main" bash -c '[[ -n "$1" ]]' _ "$_f2a_s01_parcours"
check_cmd "parcours : une partie arrivée ET une partie départ" \
  _f2a_contient "$_f2a_s01_parcours" "arriv" "départ|depart"
check_cmd "parcours : liste de contrôle en cases à cocher (au moins 10)" \
  bash -c '(( $(grep -Ec "^[[:space:]]*[-*] \[[ xX]\]" <<<"$1") >= 10 ))' _ "$_f2a_s01_parcours"
check_cmd "parcours : le départ traite jetons ou sessions, et données" \
  _f2a_contient "$_f2a_s01_parcours" "jeton|session|token" "donn(e|é)es"
