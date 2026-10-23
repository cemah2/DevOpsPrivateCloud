# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S01.sh — F4-S01 « Le processus de changement de MédiSphère » (RED publié) : présence et contenu
# minimal de docs/changements/processus.md et du modèle de fiche docs/changements/fiches/modele.md
# (sections et clés d'en-tête que les checks des scénarios suivants lisent). Lecture seule (GitLab).

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S01 — Le processus de changement de MédiSphère"
require_cmd curl jq

check_cmd "processus.md (main) : trois catégories (standard pré-approuvé, normal, urgent)" \
  _f4m_doc . '^processus\.md$' 'standard' 'normal' 'urgen'
check_cmd "processus.md : go/no-go, retour arrière, gel, revue après mise en œuvre" \
  _f4m_doc . '^processus\.md$' 'go.?/.?no.?go|no-go' 'retour arri' 'gel' 'revue'
check_cmd "processus.md : calendrier du trimestre (CHG-3404 à CHG-3413 au moins cités)" \
  _f4m_doc . '^processus\.md$' 'CHG-3404' 'CHG-3407' 'CHG-3408' 'CHG-3413'
check_cmd "processus.md : la mesure de l'interruption est exigée (sonde, avant/pendant/après)" \
  _f4m_doc . '^processus\.md$' 'interruption' 'sonde' 'avant' 'apr(e|è)s'

_f4_s01_modele="$(_f4m_fichier "$_f4m_projet_doc" "$_f4m_doc_dir/fiches/modele.md" 2>/dev/null || true)"
_f4_s01_entete() {
  local k
  [[ "$(head -n 1 <<<"$_f4_s01_modele")" == "---" ]] || return 1
  for k in chg categorie statut decision fenetre-debut fenetre-fin mesure-source mesure-debut mesure-fin \
    mesure-objectif-s mesure-interruption-s; do
    awk 'NR > 1 && $0 == "---" { exit } NR > 1' <<<"$_f4_s01_modele" | grep -Eq "^$k:" || return 1
  done
}
_f4_s01_sections() {
  local s
  for s in 'risque' 'impact' 'fen(e|ê)tre' 'pr(e|é)paration' '(É|E|é|e)tapes' 'go.?/.?no.?go|crit(e|è)res' \
    'retour arri' 'communication' 'mesure'; do
    grep -Eqi "^#+ .*($s)" <<<"$_f4_s01_modele" || return 1
  done
}
check_cmd "fiches/modele.md : en-tête YAML avec les clés de catégorie, décision, fenêtre et mesure" _f4_s01_entete
check_cmd "fiches/modele.md : sections risque, impact, fenêtre, préparation, étapes, go/no-go, retour arrière, communication, mesure" \
  _f4_s01_sections
