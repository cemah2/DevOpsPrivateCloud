# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S15.sh — F1-S15 « Rapport de reconstruction et runbook Day 0 » (RED publié).
# Présence et contenu minimal seulement (CONVENTIONS §7) : le fond s'auto-évalue avec le corrigé.
# Lecture seule : GitLab en GET (main de plateforme/medisphere).

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S15 — Rapport de reconstruction et runbook Day 0"
require_cmd curl jq

check_cmd "docs/day0/rapport-reconstruction.md : durées mesurées, estimation de S01 et écart, gestes manuels et dette, actions datées" \
  _f1c_doc '^rapport-reconstruction\.md$' 'dur[ée]e' 'estimation|estim[ée]' '[ée]cart' 'manuel' 'dette' '[0-9]{4}-[0-9]{2}-[0-9]{2}' '[0-9]+ ?(min|h)'
check_cmd "rapport : dépendances circulaires rencontrées et incident INC-5712" \
  _f1c_doc '^rapport-reconstruction\.md$' 'circulaire|poule|amor[cç]age' 'INC-5712'
check_cmd "runbook RB-310 (docs/day0/runbooks/) : VMID 2141-2146, VIP, playbooks, Helmfile, OpenBao, Argo CD, récupération CNPG, retour arrière" \
  _f1c_doc '^RB-310' '2141' '2146' '10\.10\.40\.200' 'playbook|ansible' 'helmfile' 'openbao|k8s-par1' 'argo' 'recovery|r[ée]cup[ée]ration' 'retour arri[èe]re'
check_cmd "runbook RB-310 : points de contrôle et durées de référence" \
  _f1c_doc '^RB-310' 'contr[ôo]le|v[ée]rifi' '[0-9]+ ?(min|h)'
check_cmd "ADR-0310 (docs/day0/adr/) : options comparées, décision, conséquences" \
  _f1c_doc '^ADR-0310' 'option' 'd[ée]cision' 'cons[ée]quence'
_f1_s15_rangement() {
  _f1c_doc_chemin '^RB-310' "$_f1c_doc/runbooks" >/dev/null && _f1c_doc_chemin '^ADR-0310' "$_f1c_doc/adr" >/dev/null
}
check_cmd "RB-310 sous docs/day0/runbooks/ et ADR-0310 sous docs/day0/adr/" _f1_s15_rangement
