# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E19.sh — M21-E19 : Méthodes USE et RED, les tableaux de bord de référence
# À lancer depuis adm01. Lecture seule : API de Grafana (wb-checks, Viewer), GitLab.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E19 — Méthodes USE et RED : les tableaux de bord de référence"
require_cmd jq curl

# Titres de tous les panneaux, rangées comprises (et panneaux des rangées repliées).
_M21O_E19_TITRES='[.dashboard.panels[]?, .dashboard.panels[]?.panels[]?] | map(.title // "")'

# uid:dossier:méthode
for _m21o_e19_t in plateforme-use-noeuds:plateforme:USE plateforme-use-ceph:plateforme:USE \
  mediagenda-red:mediagenda:RED medidoc-red:medidoc:RED plateforme-red-passerelle:plateforme:RED; do
  IFS=: read -r _m21o_e19_uid _m21o_e19_dossier _m21o_e19_m <<<"$_m21o_e19_t"
  _m21o_e19_j="$(_m21o_tableau "$_m21o_e19_uid")"
  check_cmd "$_m21o_e19_uid : provisionné dans le dossier $_m21o_e19_dossier" _m21o_json "$_m21o_e19_j" \
    --arg d "$_m21o_e19_dossier" '.meta.provisioned == true and .meta.folderUid == $d'
  if [[ "$_m21o_e19_m" == USE ]]; then
    check_cmd "$_m21o_e19_uid : sections Utilisation, Saturation et Erreurs" _m21o_json "$_m21o_e19_j" \
      "$_M21O_E19_TITRES"' | any(startswith("Utilisation")) and any(startswith("Saturation")) and any(startswith("Erreurs"))'
  else
    check_cmd "$_m21o_e19_uid : sections Débit, Erreurs et Durée" _m21o_json "$_m21o_e19_j" \
      "$_M21O_E19_TITRES"' | any(startswith("Débit")) and any(startswith("Erreurs")) and any(startswith("Durée"))'
  fi
  check_cmd "$_m21o_e19_uid : lien vers un runbook RB-21x, variable de source de données" _m21o_json "$_m21o_e19_j" '
    any(.dashboard.links[]?; (.url // "") | test("RB-21[0-9]"))
    and any(.dashboard.templating.list[]?; .type == "datasource")'
done
check_cmd "plateforme/medisphere : docs/observabilite/metriques/tableaux.md sur main" \
  _m21o_fichier "$_M21O_P_DOC" docs/observabilite/metriques/tableaux.md
