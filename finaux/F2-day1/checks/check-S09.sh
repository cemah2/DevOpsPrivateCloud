# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S09.sh — F2-S09 « Réponse à la demande d'accès à la production » (RED) : présence et contenu
# minimal de la réponse publiée sur main de plateforme/medisphere (docs/accueil/reponses/). La qualité
# de l'argumentation s'évalue avec le corrigé.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S09 — Réponse à la demande d'accès à la production"
require_cmd jq curl

check_cmd "docs/accueil/reponses/ : réponse au ticket DEV-3209 publiée sur main" \
  _f2b_doc "$_f2b_doc_dir"/reponses '^DEV-3209.*\.md$' 'DEV-3209'
check_cmd "la réponse motive le refus (HDS, RGPD, minimisation)" \
  _f2b_doc "$_f2b_doc_dir"/reponses '^DEV-3209.*\.md$' 'HDS' 'RGPD' 'minimis'
check_cmd "la réponse propose l'alternative (extraction pseudonymisée, base Data)" \
  _f2b_doc "$_f2b_doc_dir"/reponses '^DEV-3209.*\.md$' 'pseudonym' 'statistiques|data-traitements'
check_cmd "la réponse fixe les conditions d'un accès exceptionnel (durée, validation RSSI, traces)" \
  _f2b_doc "$_f2b_doc_dir"/reponses '^DEV-3209.*\.md$' 'exceptionnel' 'dur[ée]e|expir' 'Sophie|RSSI' 'trac|journal|audit'
