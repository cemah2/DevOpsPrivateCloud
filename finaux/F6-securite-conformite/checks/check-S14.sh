# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S14.sh — F6-S14 « Recette conformite-v1 : l'audit de suivi » (LIBRE) : écarts clos avec preuve
# dans preuves-conformite, SoA à jour, état des preuves généré, étiquette conformite-v1. Lecture seule
# (GitLab, RGW en lecture).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S14 — Recette conformite-v1 : l'audit de suivi"
require_cmd curl jq aws

# --- Écarts clos (sur main) -------------------------------------------------------------------------
for eca in ECA-3601 ECA-3602 ECA-3603 ECA-3605; do
  check_cmd "$eca clos sur main avec preuve" _f6i_doc ecarts "^$eca" 'statut:\s*clos' 'preuve'
done

# --- Preuves présentes dans le compartiment (une par écart) -----------------------------------------
if [[ ! -r "$_f6i_preuves_env" ]]; then
  _ko "identité de lecture de preuves-conformite illisible ($_f6i_preuves_env) : impossible de vérifier les preuves"
else
  for eca in ECA-3601 ECA-3602 ECA-3603 ECA-3605; do
    _s14_preuve() { [[ -n "$(_f6i_preuves_ls "$1/")" ]]; }
    check_cmd "preuve déposée dans preuves-conformite/$eca/" _s14_preuve "$eca"
  done
fi

# --- SoA à jour (mesures touchées par le F6) --------------------------------------------------------
check_cmd "soa.md (main) : mesures du F6 à jour avec lien de preuve (journalisation, vulnérabilités, incident)" \
  _f6i_doc . '^soa' 'A\.8\.15|journalis' 'A\.8\.8|vuln(é|e)rabilit' 'A\.5\.2(4|5|6)|incident' 'preuve|preuves-conformite'

# --- État des preuves généré ------------------------------------------------------------------------
_s14_etat_outil() { _f6i_arbre plateforme/outils 2>/dev/null | grep -Eqi 'etat-preuves'; }
check_cmd "outil d'état des preuves présent sur main (etat-preuves)" _s14_etat_outil
check_cmd "état des preuves publié (docs/conformite/etat-preuves.md)" \
  _f6i_doc . '^etat-preuves' 'preuve|ECA-36' 'inalt(é|e)rab|verrou|fra(î|i)cheur|date'

# --- Étiquette finale -------------------------------------------------------------------------------
check_cmd "étiquette conformite-v1 posée sur plateforme/medisphere" _f6i_etiquette conformite-v1
