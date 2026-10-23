# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S14.sh — F2-S14 « Retour d'expérience et feuille de route » (RED) : présence et contenu minimal
# de docs/accueil/retour-experience.md sur main de plateforme/medisphere. La qualité s'évalue avec le
# corrigé.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S14 — Retour d'expérience et feuille de route"
require_cmd jq curl

_s14_f="$_f2b_doc_dir"/retour-experience.md
check_cmd "$_s14_f publié sur main (au moins cinq sections)" _f2b_doc_sections "$_s14_f" 5 'Day 1|accueil'
check_cmd "délais mesurés (premier déploiement, création d'équipe, demandes)" \
  _f2b_fichier_contient "$_f2b_projet_doc" "$_s14_f" 'premier d[ée]ploiement' 'd[ée]lai' '[0-9]+ ?(h|j|min|jours|heures)'
check_cmd "frictions et tickets analysés (PLAT-, DEV-, SEC-)" \
  _f2b_fichier_contient "$_f2b_projet_doc" "$_s14_f" 'friction' '(PLAT|DEV|SEC)-32[0-9]{2}'
check_cmd "satisfaction recueillie auprès d'Inès, Hugo et Marc" \
  _f2b_fichier_contient "$_f2b_projet_doc" "$_s14_f" 'In[èe]s' 'Hugo' 'Marc' 'satisfaction|note|avis'
check_cmd "feuille de route trimestrielle priorisée" \
  _f2b_fichier_contient "$_f2b_projet_doc" "$_s14_f" 'feuille de route' 'T[1-4]|trimestre' 'priorit'
