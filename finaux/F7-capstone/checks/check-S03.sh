# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S03.sh — F7-S03 « L'architecture cible de production » (RED publié) : présence et contenu minimal
# de docs/capstone/architecture.md (sections, schéma, dimensionnement fondé sur une mesure, serveurs par
# site, écarts avec le lab). Lecture seule (GitLab). La qualité de la conception se juge avec le corrigé.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S03 — L'architecture cible de production"
require_cmd curl jq

_f7c_charger architecture.md
_f7_s03="$(_f7c_doc architecture.md)"

check_cmd "architecture.md présent sur main ($_f7c_doc_dir/)" _f7c_doc_present architecture.md
if [[ -z "$_f7_s03" ]]; then
  skip "contenu de l'architecture" "document absent"
else
  check_cmd "sections : vue d'ensemble, PAR1, PAR2, exposition, bascule, dimensionnement, écarts avec le lab, points uniques de défaillance" \
    _f7c_doc_sections architecture.md "vue d.ensemble|sch(é|e)ma|synth(è|e)se" 'PAR1|principal' 'PAR2|repli|secours' \
    'exposition|internet' 'PRA|bascule|reprise' 'dimensionnement|capacit' 'lab' 'point.*unique|SPOF|d(é|e)faillance'
  _f7_s03_schema() { grep -Eq '```mermaid|!\[[^]]*\]\(|┌|└|[+]-{3,}' <<<"$_f7_s03"; }
  check_cmd "un schéma est présent (bloc Mermaid, image versionnée ou schéma texte)" _f7_s03_schema
  check_cmd "dimensionnement fondé sur une mesure de charge (k6, testid, référence du M29)" \
    _f7c_doc_contient architecture.md 'k6|testid|M29|TestRun' 'req(u(ê|e)tes)?[[:space:]]*(/|par)[[:space:]]*s'
  check_cmd "dimensionnement chiffré en calcul (vCPU ou cœurs), mémoire (Go) et stockage (To)" \
    _f7c_doc_contient architecture.md '[0-9][[:space:]]*(vCPU|c(œ|oe)urs)' '[0-9][[:space:]]*(Go|Gio|GB)' '[0-9][[:space:]]*(To|Tio|TB)'
  _f7_s03_serveurs() {
    (($(grep -Eoi '([0-9]+|deux|trois|quatre|cinq|six|sept|huit)( \*\*| )?(hyperviseurs|serveurs|n(œ|oe)uds physiques)' <<<"$_f7_s03" | grep -c . || true) >= 2))
  }
  check_cmd "le nombre de serveurs (hyperviseurs) est écrit pour chaque site" _f7_s03_serveurs
  check_cmd "écarts avec le lab : exposition Internet, site de repli, fournisseur d'identité, interconnexion" \
    _f7c_section_contient architecture.md 'lab' 'internet|exposition' 'PAR2|hp01|repli' 'idp|identit|keycloak' \
    'wireguard|interconnexion|liaison'
fi
