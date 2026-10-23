# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S10.sh — F6-S10 « Prêts pour l'incident » (LIBRE, ferme ECA-3605) : RB-360 et RB-361 sur main,
# contrôle du kit forensique versionné, capture éprouvée et documentée, exercice de table consigné,
# ECA-3605 clos. Lecture seule (GitLab).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S10 — Prêts pour l'incident (ECA-3605)"
require_cmd curl jq

_s10_rb="$_f6i_inc_dir/runbooks"
check_cmd "RB-360 sur main (réponse à incident : rôles, gravités, volet réglementaire, liens RB-262 et RB-361)" \
  _f6i_doc "$_s10_rb" '^RB-360' 'r(ô|o)le' 'gravit' 'RB-361' 'RB-262' 'CNIL|r(é|e)glementaire'
check_cmd "RB-361 sur main (forensique : ordre de collecte, empreintes, dépôt dans preuves-conformite)" \
  _f6i_doc "$_s10_rb" '^RB-361' 'collect' 'empreinte|SHA' 'preuves-conformite'
check_cmd "RB-361 : capture d'un conteneur vivant éprouvée sur le lab (point de contrôle ou copie, résultat écrit)" \
  _f6i_doc "$_s10_rb" '^RB-361' '(é|e)prouv' 'point de contr(ô|o)le|checkpoint' 'copie'
_s10_kit() { _f6c_arbre plateforme/outils bin | grep -Eq '^bin/(ms-)?verifier-kit-forensique'; }
check_cmd "plateforme/outils (main) : contrôle du kit forensique bin/…verifier-kit-forensique" _s10_kit
check_cmd "compte rendu d'exercice de table sur main (docs/securite/incidents/exercices/), avec actions" \
  _f6i_doc "$_f6i_inc_dir/exercices" '\.md$' 'exercice' 'sc(é|e)nario|d(é|e)roul' 'action' '20[0-9]{2}-[0-9]{2}-[0-9]{2}'
check_cmd "ECA-3605 clos sur main (statut, date de clôture, lot de preuve antérieur à la clôture)" _f6c_ecart_clos 3605
