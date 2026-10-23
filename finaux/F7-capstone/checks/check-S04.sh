# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S04.sh — F7-S04 « Les décisions d'architecture » (RED publié) : au moins WB_F7_MIN_ADR (4)
# ADR-037x dans docs/capstone/adr/, chacune avec un statut, les sections contexte, décision, options et
# conséquences et au moins une exigence du cahier des charges ; ensemble, au moins quatre des cinq sujets
# (isolation, clés, identité, PRA, réversibilité). Lecture seule (GitLab).

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S04 — Les décisions d'architecture"
require_cmd curl jq

mapfile -t _f7_s04_adr < <(_f7c_docs_dossier adr '^ADR-037[0-9][^/]*\.md$')
_f7_s04_n="${#_f7_s04_adr[@]}"
_f7_s04_nb_ok() { ((_f7_s04_n >= _f7c_min_adr)); }
check_cmd "au moins $_f7c_min_adr ADR-037x dans $_f7c_doc_dir/adr/ sur main ($_f7_s04_n trouvées)" _f7_s04_nb_ok

_f7_s04_conformes=0
_f7_s04_titres=""
for _f7_s04_f in "${_f7_s04_adr[@]}"; do
  _f7_s04_nom="${_f7_s04_f#"$_f7c_doc_dir"/}"
  _f7c_charger "$_f7_s04_nom"
  _f7_s04_c="$(_f7c_doc "$_f7_s04_nom")"
  _f7_s04_titres+="$(grep -m1 -E '^#[[:space:]]' <<<"$_f7_s04_c")"$'\n'
  if _f7c_doc_contient "$_f7_s04_nom" 'statut' &&
    _f7c_doc_sections "$_f7_s04_nom" 'contexte' 'd(é|e)cision' 'options|alternatives' 'cons(é|e)quences' &&
    (($(_f7c_nb_ids "$_f7_s04_c" "$_F7C_RE_CDC") >= 1)); then
    _f7_s04_conformes=$((_f7_s04_conformes + 1))
  else
    _ko "${_f7_s04_f##*/} : statut, sections (contexte, décision, options, conséquences) ou exigence du cahier des charges manquants"
  fi
done
if ((_f7_s04_n > 0)); then
  _f7_s04_struct_ok() { ((_f7_s04_conformes == _f7_s04_n && _f7_s04_conformes >= _f7c_min_adr)); }
  check_cmd "structure complète : $_f7_s04_conformes ADR sur $_f7_s04_n (statut, contexte, décision, options, conséquences, exigence citée)" \
    _f7_s04_struct_ok
  _f7_s04_sujets() {
    local n=0 s
    for s in 'isolation|locataire|cloisonnement' 'cl(é|e)s?|chiffrement|transit' 'identit|f(é|e)d(é|e)ration|authentification|oidc' \
      'PRA|reprise|repli|sinistre' 'r(é|e)versibilit|export|restitution'; do
      grep -Eqi -- "$s" <<<"$_f7_s04_titres" && n=$((n + 1))
    done
    ((n >= 4))
  }
  check_cmd "sujets couverts par les titres : au moins 4 parmi isolation, clés, identité, PRA, réversibilité" _f7_s04_sujets
else
  skip "structure et sujets des ADR" "aucune ADR-037x"
fi
