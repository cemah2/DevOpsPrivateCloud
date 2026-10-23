# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S02.sh — F5-S02 « Les dépendances de la reprise et l'architecture de PAR2 » (RED publié) :
# présence et contenu minimal de docs/pra/dependances.md et de l'ADR-0350. Lecture seule.

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S02 — Les dépendances de la reprise et l'architecture de PAR2"
require_cmd curl jq

_f5_s02_dep="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/dependances.md" 2>/dev/null || true)"
check_cmd "dependances.md présent sur main" test -n "$_f5_s02_dep"
_f5_s02_couverture() {
  local m
  for m in 'DNS|dns03|zone' 'PKI|certificat' 'openbao' 'kms01' 'image|registre|reg02' 'git|miroir' 'tofu|(é|e)tat' \
    'wal|cnpg|base' 's3|objet' 'NTP|heure|temps|chrony' 'identit|bris de glace|acc(è|e)s'; do
    grep -Eqi -- "$m" <<<"$_f5_s02_dep" || return 1
  done
}
check_cmd "dependances.md : DNS, PKI, OpenBao et kms01, images, Git, état OpenTofu, données, temps, accès" _f5_s02_couverture
_f5_s02_vagues() { (($(grep -Eci 'vague|(é|e)tape [0-9]' <<<"$_f5_s02_dep") >= 3)) && grep -Eqi 'condition|crit(è|e)re|passage' <<<"$_f5_s02_dep"; }
check_cmd "dependances.md : ordre de redémarrage par vagues avec conditions de passage" _f5_s02_vagues
_f5_s02_boucles() { (($(grep -Eci 'boucle|circulaire|amor(ç|c)age|(œ|oe)uf' <<<"$_f5_s02_dep") >= 3)); }
check_cmd "dependances.md : au moins trois boucles (dépendances circulaires) et leur amorçage" _f5_s02_boucles

_f5_s02_adr="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/adr/ADR-0350-site-de-repli-par2.md" 2>/dev/null || true)"
check_cmd "adr/ADR-0350-site-de-repli-par2.md présent sur main" test -n "$_f5_s02_adr"
check_cmd "ADR-0350 : statut, contexte, options, décision, conséquences, risques" \
  _f5p_sections "$_f5_s02_adr" 'contexte' 'option' 'd(é|e)cision' 'cons(é|e)quence' 'risque'
_f5_s02_statut() { grep -Eqi 'statut' <<<"$_f5_s02_adr"; }
check_cmd "ADR-0350 : statut renseigné" _f5_s02_statut
_f5_s02_options() {
  local n=0 m
  for m in 'reconstru|sauvegardes? seules?|(à|a) froid' 'ti(è|e)de' 'chaud' 'prestataire|externe|cloud public|h(é|e)bergeur'; do
    grep -Eqi -- "$m" <<<"$_f5_s02_adr" && n=$((n + 1))
  done
  ((n >= 3))
}
check_cmd "ADR-0350 : au moins trois options comparées (froid, tiède, chaud, externe)" _f5_s02_options
