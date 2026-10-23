# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S13.sh — F2-S13 « Recette Day 1 » (contrôle agrégé) : outil ms-verif-equipe publié dans
# plateforme/outils (pipeline vert), vérifications des scénarios porteurs d'état toutes vertes
# (S02, S04, S05, S07, S08, S11, S12 : relancées ici), rapport de recette publié, aucune panne F2 ouverte,
# étiquette day1-v1 posée sur plateforme/medisphere. Lecture seule.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S13 — Recette Day 1"
require_cmd jq curl kubectl

_s13_racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
read -r -a _s13_scenarios <<<"${WB_F2_S13_SCENARIOS:-02 04 05 07 08 11 12}"

# --- 1. L'outil --------------------------------------------------------------------------------------
check_cmd "plateforme/outils : bin/ms-verif-equipe sur main (locataire, quotas, AppProject, alertes, catalogue)" \
  _f2b_fichier_contient "$_f2b_projet_outils" bin/ms-verif-equipe 'Tenant|locataire' 'ResourceQuota|quota' \
  'AppProject' 'alertmanager|route' 'backstage|catalog' 'ServiceLevelObjective|SLO'
check_cmd "plateforme/outils : un test de ms-verif-equipe dans la CI (.gitlab-ci.yml)" \
  _f2b_fichier_contient "$_f2b_projet_outils" .gitlab-ci.yml 'ms-verif-equipe'
check_cmd "plateforme/outils : dernier pipeline de main réussi" _f2b_pipeline_ok "$_f2b_projet_outils"

# --- 2. Les scénarios porteurs d'état ------------------------------------------------------------------
for _s13_n in "${_s13_scenarios[@]}"; do
  _s13_sortie="$(bash "$_s13_racine/lab/bin/check" F2 "$_s13_n" 2>&1)" && _s13_rc=0 || _s13_rc=$?
  if ((_s13_rc != 0)); then
    # On montre les lignes en KO du sous-contrôle (sans couleurs) pour orienter la reprise.
    while IFS= read -r _s13_l; do
      printf '          S%s %s\n' "$_s13_n" "$_s13_l"
    done < <(tr -d '\033' <<<"$_s13_sortie" | grep -E '\[KO\]|\[!!\]|introuvable|Pas de script' || true)
  fi
  check_cmd "lab/bin/check F2 $_s13_n vert" test "$_s13_rc" -eq 0
done

# --- 3. Rapport, pannes, étiquette ---------------------------------------------------------------------
check_cmd "rapport de recette docs/accueil/recette-day1.md (ms-verif-equipe pour chaque équipe, délais mesurés)" \
  _f2b_doc_sections "$_f2b_doc_dir"/recette-day1.md 3 'ms-verif-equipe' "${_f2b_equipes[@]}" 'd[ée]lai'
_s13_pannes() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'F2-S*' 2>/dev/null)" ]]
}
check_cmd "aucune panne F2 ouverte (lab/bin/break F2 <XX> --annuler)" _s13_pannes
check_cmd "plateforme/medisphere : étiquette day1-v1 posée" _f2b_etiquette "$_f2b_projet_doc" day1-v1
