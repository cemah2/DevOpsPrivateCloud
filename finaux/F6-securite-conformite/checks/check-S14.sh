# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S14.sh — F6-S14 « Recette conformite-v1 : l'audit de suivi » (LIBRE) : écarts clos avec un lot de
# preuve existant et antérieur à la clôture, SoA à jour, état des preuves généré, collecte planifiée,
# étiquette conformite-v1. Lecture seule (GitLab, RGW en lecture).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S14 — Recette conformite-v1 : l'audit de suivi"
require_cmd curl jq aws

# --- Écarts clos (sur main), avec leur lot de preuve ------------------------------------------------
_f6c_preuves_identite ||
  _ko "identité de lecture des preuves illisible ($_f6c_preuves_env) : l'existence des lots de clôture n'est pas vérifiée"
for _s14_n in 3601 3602 3603 3605; do
  check_cmd "ECA-$_s14_n clos sur main, son lot de preuve existe dans $_f6c_bucket et précède la clôture" _f6c_ecart_clos "$_s14_n"
done

# --- SoA à jour (mesures touchées par le F6) --------------------------------------------------------
check_cmd "soa.md (main) : journalisation, vulnérabilités et incidents renvoient à une preuve" \
  _f6c_doc . '^soa\.md$' '8\.15' '8\.8' '5\.2(4|5|6)' 'P-[A-Z]{2,4}-[0-9]{2}|preuves-conformite'

# --- État des preuves généré, collecte planifiée -------------------------------------------------------
_s14_etat_outil() { _f6c_arbre "$_f6c_outils" bin | grep -Eq '^bin/(ms-)?etat-preuves'; }
check_cmd "plateforme/outils (main) : générateur de l'état des preuves bin/…etat-preuves" _s14_etat_outil
check_cmd "docs/conformite/etat-preuves.md (main) : état généré (écarts, lots, verrouillage, fraîcheur)" \
  _f6c_doc . '^etat-preuves\.md$' 'ECA-36' 'lots/' 'verrou' 'g(é|e)n(é|e)r'
check_cmd "plateforme/outils : un pipeline planifié de main a réussi récemment (collecte des preuves)" \
  _f6c_pipelines_planifies_ok "$_f6c_outils" 10

# --- Étiquette finale -------------------------------------------------------------------------------
check_cmd "étiquette conformite-v1 posée sur $_f6c_doc_projet" _f6i_etiquette conformite-v1
