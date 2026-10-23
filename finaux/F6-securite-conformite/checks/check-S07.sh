# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S07.sh — F6-S07 « Rapport d'écarts et plan de remédiation » (RED publié) : présence et contenu
# minimal du rapport d'écarts, des fiches ECA-3601 à ECA-3606, du plan de remédiation et de la
# cartographie des transferts hors EEE. Lecture seule (GitLab). La qualité se juge avec le corrigé.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S07 — Rapport d'écarts et plan de remédiation"
require_cmd curl jq

_f6_s07_r="$(_f6c_contenu audit-2026/rapport-ecarts.md)"
check_cmd "audit-2026/rapport-ecarts.md (main) : les six écarts de l'audit (ECA-3601 à 3606) et ceux de S04" \
  _f6c_contient "$_f6_s07_r" 'ECA-3601' 'ECA-3602' 'ECA-3603' 'ECA-3604' 'ECA-3605' 'ECA-3606' 'ECA-361[1-9]'
check_cmd "rapport d'écarts : synthèse, méthode, gravité (majeur/mineur), points forts" \
  _f6c_contient "$_f6_s07_r" 'synth(è|e)se' 'm(é|e)thode' 'majeur' 'mineur' 'point(s)? fort'

_f6_s07_fiche() {
  local n="$1" f
  for f in $(_f6c_arbre "$_f6c_doc_projet" "$_f6c_doc_dir/ecarts" | grep -E "/ECA-$n([-_.][^/]*)?\\.md\$"); do
    _f6c_contient "$(_f6c_fichier "$_f6c_doc_projet" "$f" 2>/dev/null || true)" \
      'constat' 'preuve' '(5|6|7|8)\.[0-9]+' 'HDS|exigence' 'majeur|mineur|gravit(é|e)|criticit(é|e)' && return 0
  done
  return 1
}
for _f6_s07_n in 3601 3602 3603 3604 3605 3606; do
  check_cmd "ecarts/ECA-$_f6_s07_n.md : constat, preuve, mesure ISO, exigence, gravité" _f6_s07_fiche "$_f6_s07_n"
done

_f6_s07_p="$(_f6c_contenu plan-remediation.md)"
check_cmd "plan-remediation.md : chaque écart 3601-3606 a une action, un responsable et une échéance" \
  _f6c_contient "$_f6_s07_p" 'ECA-3601' 'ECA-3602' 'ECA-3603' 'ECA-3604' 'ECA-3605' 'ECA-3606' 'responsable|porteur' '(é|e)ch(é|e)ance|20[0-9]{2}-[0-9]{2}'
check_cmd "plan-remediation.md : priorisé par le risque (vraisemblance, impact ou niveau de risque)" \
  _f6c_contient "$_f6_s07_p" 'risque' 'priorit(é|e)' 'impact|vraisemblance|probabilit(é|e)'
_f6_s07_t="$(_f6c_contenu transferts-hors-eee.md)"
check_cmd "transferts-hors-eee.md : cartographie (fournisseur, donnée, pays, base, mesures) validée par le DPO" \
  _f6c_contient "$_f6_s07_t" 'EEE' 'pays' 'fournisseur|sous-traitant|prestataire' 'mesure|garantie' 'Thomas Renaud|DPO'
