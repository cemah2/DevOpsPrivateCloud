# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F6-S10 « Prêts pour l'incident » (LIBRE, ferme ECA-3605) : RB-360 et RB-361 sur main,
# contrôle du kit forensique présent, capture d'un conteneur documentée, exercice de table rédigé,
# ECA-3605 clos. Lecture seule (GitLab).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S10 — Prêts pour l'incident (ECA-3605)"
require_cmd curl jq

check_cmd "RB-360 sur main (réponse à incident : rôles, gravités, volet réglementaire, lien RB-262/RB-361)" \
  _f6i_doc "$_f6i_inc_dir/runbooks" '^RB-360' 'r(ô|o)le' 'gravit' 'RB-361' 'RB-262' 'CNIL|r(é|e)glementaire'
check_cmd "RB-361 sur main (forensique conteneur : ordre de collecte, capture, empreintes, dépôt)" \
  _f6i_doc "$_f6i_inc_dir/runbooks" '^RB-361' 'collect' 'empreinte|SHA' 'preuves-conformite|preuves' 'point de contr(ô|o)le|checkpoint|copie'
# Recherche du contrôle du kit dans l'un des deux projets.
_s10_kit() {
  _f6i_arbre plateforme/outils 2>/dev/null | grep -Eqi 'verifier-kit|kit-forensique' \
    || _f6i_arbre plateforme/k8s 2>/dev/null | grep -Eqi 'verifier-kit|kit-forensique'
}
check_cmd "contrôle du kit forensique présent sur main (verifier-kit-forensique)" _s10_kit
check_cmd "capacité de capture d'un conteneur documentée dans RB-361 (point de contrôle ou copie, résultat sur le lab)" \
  _f6i_doc "$_f6i_inc_dir/runbooks" '^RB-361' '(é|e)prouv|confirm|lab' 'point de contr(ô|o)le|checkpoint|copie'
check_cmd "compte rendu d'exercice de table sur main (docs/securite/incidents/exercices/)" \
  _f6i_doc "$_f6i_inc_dir/exercices" 'exercice' 'sc(é|e)nario|d(é|e)roul' 'action'
check_cmd "ECA-3605 clos sur main avec preuve" _f6i_doc ecarts '^ECA-3605' 'statut:\s*clos' 'preuve'
