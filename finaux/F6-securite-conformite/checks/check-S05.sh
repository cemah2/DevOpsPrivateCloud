# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S05.sh — F6-S05 « L'audit technique outillé » (LIBRE) : rapport d'audit technique publié
# (docs/conformite/audit-2026/audit-technique.md) couvrant les outils du M26, résultats bruts versionnés
# à côté (technique/), tri et faux positifs justifiés. Lecture seule (GitLab). La pertinence du tri se
# juge avec le corrigé.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S05 — L'audit technique outillé"
require_cmd curl jq

_f6_s05_r="$(_f6c_contenu audit-2026/audit-technique.md)"
check_cmd "audit-technique.md (main) : OpenSCAP, kube-bench, kubescape, Trivy, ssh-audit" \
  _f6c_contient "$_f6_s05_r" 'OpenSCAP|oscap' 'kube-bench' 'kubescape' 'Trivy|Harbor' 'ssh-audit'
check_cmd "audit-technique.md : versions des outils, référentiels et périmètre analysé" \
  _f6c_contient "$_f6_s05_r" 'version' 'CIS' 'ANSSI|BP-028' 'k8s-par1'
check_cmd "audit-technique.md : résultats triés par gravité, faux positifs justifiés, renvois aux écarts" \
  _f6c_contient "$_f6_s05_r" 'critique' '(é|e)lev(é|e)e?' 'faux positif' 'ECA-36[0-9]{2}|(é|e)cart'
_f6_s05_bruts() { (($(_f6c_arbre "$_f6c_doc_projet" "$_f6c_doc_dir/audit-2026/technique" | grep -c .) >= 5)); }
check_cmd "audit-2026/technique/ : au moins cinq fichiers de résultats bruts (un par outil)" _f6_s05_bruts
_f6_s05_empreintes() { grep -Eq '[0-9a-f]{64}' <<<"$_f6_s05_r"; }
check_cmd "audit-technique.md : empreintes SHA-256 des résultats bruts (intégrité de la preuve)" _f6_s05_empreintes
