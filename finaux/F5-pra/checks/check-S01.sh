# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S01.sh — F5-S01 « Analyse d'impact et objectifs de reprise » (RED publié) : présence et contenu
# minimal de docs/pra/bia.md et docs/pra/objectifs.md. Lecture seule (GitLab, ou miroir de adm02 si
# WB_F5_SOURCE_DOC=miroir). La qualité de l'analyse s'évalue avec le corrigé.

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S01 — Analyse d'impact et objectifs de reprise"
require_cmd curl jq

check_cmd "bia.md (main) : les quatre services du périmètre (MédiAgenda, MédiDoc, Legacy-RDV, MédiNotif)" \
  _f5p_doc bia.md 'm(é|e)diagenda' 'm(é|e)didoc' 'legacy' 'm(é|e)dinotif'
check_cmd "bia.md : impacts dans le temps (1 h, 4 h, 1 jour…) et durée maximale d'interruption admissible" \
  _f5p_doc bia.md '(1|une) ?h' '(4|quatre) ?h' 'jour' 'interruption (maximale )?admissible|DMIA|MTPD|dur(é|e)e maximale'
check_cmd "bia.md : perte de données maximale admissible et procédures manuelles d'attente" \
  _f5p_doc bia.md 'perte (de donn(é|e)es )?maximale|PDMA|MTDL' 'manuel|d(é|e)grad|papier|t(é|e)l(é|e)phone'

_f5_s01_obj="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/objectifs.md" 2>/dev/null || true)"
check_cmd "objectifs.md présent sur main" test -n "$_f5_s01_obj"
_f5_s01_rto_rpo() {
  local s
  grep -Eqi 'RTO' <<<"$_f5_s01_obj" && grep -Eqi 'RPO' <<<"$_f5_s01_obj" || return 1
  for s in 'm(é|e)diagenda' 'm(é|e)didoc' 'legacy' 'm(é|e)dinotif'; do
    # Chaque service apparaît sur une ligne qui porte une durée (tableau ou liste).
    grep -Eqi -- "$s.*[0-9]+ ?(min|h|heure|jour)" <<<"$_f5_s01_obj" || return 1
  done
}
check_cmd "objectifs.md : un RTO et un RPO chiffrés pour chacun des quatre services" _f5_s01_rto_rpo
check_cmd "objectifs.md : mode dégradé et définition de la fin de reprise" \
  grep -Eqi 'd(é|e)grad' <<<"$_f5_s01_obj"
_f5_s01_fin() { grep -Eqi 'fin de (la )?reprise|reprise (est )?(atteinte|acquise|constat)|horloge|chronom' <<<"$_f5_s01_obj"; }
check_cmd "objectifs.md : l'instant où s'arrête l'horloge du RTO est défini" _f5_s01_fin
_f5_s01_perimetre() { grep -Eqi 'p(é|e)rim(è|e)tre' <<<"$_f5_s01_obj" && grep -Eqi 'm(é|e)divisio' <<<"$_f5_s01_obj" && grep -Eqi '\bdata\b' <<<"$_f5_s01_obj" && grep -Eqi 'exclu|hors (du )?(PRA|p(é|e)rim)' <<<"$_f5_s01_obj"; }
check_cmd "objectifs.md : périmètre du PRA v1, MédiVisio et Data tranchés, exclusions motivées" _f5_s01_perimetre
