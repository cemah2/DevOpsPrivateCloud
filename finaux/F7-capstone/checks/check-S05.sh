# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S05.sh — F7-S05 « Chiffrage et coût complet sur cinq ans » (RED publié) : présence et contenu
# minimal de docs/capstone/chiffrage.md, format et cohérence arithmétique de docs/capstone/chiffrage.csv
# (colonnes, trois scénarios, CAPEX et OPEX, total = somme des cinq années). Lecture seule (GitLab).
# La justesse des hypothèses et des prix se juge avec le corrigé.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S05 — Chiffrage et coût complet sur cinq ans"
require_cmd curl jq

_f7c_charger chiffrage.md chiffrage.csv
_f7_s05_csv="$(_f7c_doc chiffrage.csv)"

check_cmd "chiffrage.md présent sur main ($_f7c_doc_dir/)" _f7c_doc_present chiffrage.md
if _f7c_doc_present chiffrage.md; then
  check_cmd "chiffrage.md : prix datés (octobre 2026) et marqués « à vérifier », hypothèses explicites" \
    _f7c_doc_contient chiffrage.md '(à|a) v(é|e)rifier' 'octobre 2026|10/2026|2026-10' 'hypoth'
  check_cmd "chiffrage.md : comparaisons nuage public HDS et infogérance, prix proposé, sensibilité, recommandation" \
    _f7c_doc_contient chiffrage.md 'nuage|cloud' 'infog(é|e)r' 'P2|redevance' 'sensibilit' 'recommand'
  check_cmd "chiffrage.md : coût sur cinq ans, personnel compté (ETP)" \
    _f7c_doc_contient chiffrage.md '(5|cinq) ans' 'ETP|temps plein'
else
  skip "contenu de chiffrage.md" "document absent"
fi

check_cmd "chiffrage.csv présent sur main" _f7c_doc_present chiffrage.csv
if [[ -n "$_f7_s05_csv" ]]; then
  check_cmd "chiffrage.csv : même nombre de champs sur chaque ligne (séparateur virgule ou point-virgule)" \
    _f7c_csv_valide "$_f7_s05_csv"
  check_cmd "chiffrage.csv : colonnes scenario, poste, categorie, annee_1 à annee_5, total_5_ans, hypothese" \
    _f7c_csv_colonnes "$_f7_s05_csv" scenario poste categorie annee_1 annee_2 annee_3 annee_4 annee_5 total_5_ans hypothese
  _f7_s05_nsc="$(_f7c_csv_nb_distinct "$_f7_s05_csv" scenario)"
  _f7_s05_sc_ok() { ((${_f7_s05_nsc:-0} >= 3)); }
  check_cmd "chiffrage.csv : au moins trois scénarios (${_f7_s05_nsc:-0} trouvés)" _f7_s05_sc_ok
  _f7_s05_cat_ok() {
    local v
    v="$(_f7c_csv_valeurs "$_f7_s05_csv" categorie | tr '[:lower:]' '[:upper:]' | sort -u)"
    grep -qx 'CAPEX' <<<"$v" && grep -qx 'OPEX' <<<"$v"
  }
  check_cmd "chiffrage.csv : lignes CAPEX et lignes OPEX" _f7_s05_cat_ok
  check_cmd "chiffrage.csv : sur chaque ligne, total_5_ans = annee_1 + … + annee_5" _f7c_csv_totaux_ok "$_f7_s05_csv"
else
  skip "format de chiffrage.csv" "tableur absent"
fi
