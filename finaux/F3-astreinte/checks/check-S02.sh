# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S02.sh — F3-S02 « La procédure de gestion d'incident » (RED publié) : présence et contenu minimal
# de docs/exploitation/gestion-incidents.md sur main. L'appréciation de la qualité se fait avec le corrigé.

# shellcheck source=_f3-sante.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-sante.sh"

title "F3-S02 — La procédure de gestion d'incident"
require_cmd jq curl

_f3d_s02="$_f3s_doc/gestion-incidents.md"
_f3s_doc_present "$_f3d_s02" "procédure publiée ($_f3d_s02)"
for _f3d_n in 1 2 3 4; do
  _f3s_doc_contient "$_f3d_s02" "SEV ?$_f3d_n" "niveau de gravité SEV$_f3d_n défini"
done
_f3s_doc_contient "$_f3d_s02" "responsable d.incident" "rôle : responsable d'incident"
_f3s_doc_contient "$_f3d_s02" "communication" "rôle : communication"
_f3s_doc_contient "$_f3d_s02" "technique|expert" "rôle : technique"
_f3s_doc_contient "$_f3d_s02" "canal|canaux" "canaux de communication"
_f3s_doc_contient "$_f3d_s02" "toutes les [0-9]+ ?min" "rythme des messages d'état (toutes les N min)"
_f3s_doc_contient "$_f3d_s02" "mod[èe]le" "modèles de messages"
_f3s_doc_contient "$_f3d_s02" "main courante" "main courante"
_f3s_doc_contient "$_f3d_s02" "\[ouverture\]|INC-59[0-9X]{2} \[" "format des entrées de main courante"
_f3s_doc_contient "$_f3d_s02" "cl[ôo]ture|clore" "critères de clôture"
_f3s_doc_contient "$_f3d_s02" "post-mortem" "déclenchement du post-mortem"
