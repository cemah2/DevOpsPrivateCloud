# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M21-E17 : Tableaux de bord as code
# À lancer depuis adm01. Lecture seule : API de Grafana (compte de service wb-checks, Viewer),
# GitLab (fichiers et pipelines).

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E17 — Tableaux de bord as code"
require_cmd jq curl

# Filtre jq : aucune source de données codée en dur dans le modèle du tableau (variables seulement).
_M21O_E17_SOURCES='[.dashboard | .. | objects | select(has("datasource")) | .datasource
  | if type == "object" then (.uid // null) else . end | select(. != null)]
  | all(test("^\\$") or . == "grafana" or . == "-- Grafana --" or . == "-- Mixed --" or . == "-- Dashboard --")'

for _m21o_e17_d in plateforme mediagenda medidoc; do
  check_output "dossier Grafana d'UID $_m21o_e17_d visible par le compte des vérifications" "\"uid\": *\"$_m21o_e17_d\"" \
    grafana_api "folders/$_m21o_e17_d"
done

_m21o_e17_t="$(_m21o_tableau mediagenda-apercu)"
check_cmd "tableau mediagenda-apercu : provisionné, dans le dossier mediagenda" _m21o_json "$_m21o_e17_t" \
  '.meta.provisioned == true and .meta.folderUid == "mediagenda"'
check_cmd "tableau mediagenda-apercu : aucune source de données codée en dur" _m21o_json "$_m21o_e17_t" "$_M21O_E17_SOURCES"
check_cmd "un seul tableau « MédiAgenda — aperçu » (l'ancien, fait à la main, est supprimé)" _m21o_json \
  "$(grafana_api "search?type=dash-db&query=$(_m21o_uri 'MédiAgenda — aperçu')" 2>/dev/null || true)" \
  '[.[] | select(.title == "MédiAgenda — aperçu")] | length == 1'

# Chaque fichier JSON de tableaux/ (main) correspond à un tableau provisionné, au bon dossier.
_m21o_e17_fichiers="$(_m21o_arbre "$_M21O_P_OBS" tableaux | grep -E '\.json$' || true)"
_m21o_e17_tous_provisionnes() {
  local f uid dossier t n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    dossier="$(cut -d/ -f2 <<<"$f")"
    uid="$(_m21o_contenu "$_M21O_P_OBS" "$f" | jq -r '.uid // empty' 2>/dev/null || true)"
    [[ -n "$uid" ]] || { echo "sans uid : $f"; return 1; }
    t="$(_m21o_tableau "$uid")"
    _m21o_json "$t" --arg d "$dossier" '.meta.provisioned == true and .meta.folderUid == $d' \
      || { echo "non provisionné ou mal rangé : $uid"; return 1; }
    n=$((n + 1))
  done <<<"$_m21o_e17_fichiers"
  (( n >= 1 ))
}
check_cmd "chaque fichier de tableaux/ sur main est un tableau provisionné dans le dossier de son équipe" \
  _m21o_e17_tous_provisionnes

check_cmd "plateforme/observabilite : outils/valider-tableaux.py sur main" \
  _m21o_fichier "$_M21O_P_OBS" outils/valider-tableaux.py
check_cmd "plateforme/observabilite : le job valider-tableaux du dernier pipeline de main a réussi" \
  _m21o_job_ok "$_M21O_P_OBS" valider-tableaux
_m21o_e17_etat() {
  local f
  for f in $(_m21o_arbre "$_M21O_P_INFRA" observabilite-grafana | grep -E '\.tf$' || true); do
    _m21o_contenu "$_M21O_P_INFRA" "$f"
  done
}
check_output "plateforme/infra : état observabilite-grafana (dossiers et permissions) sur main" \
  'resource +"grafana_folder_permission"' _m21o_e17_etat
