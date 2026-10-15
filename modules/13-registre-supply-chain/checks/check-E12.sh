# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E12.sh — M13-E12 : Revue : la chaîne de livraison du stagiaire
# Contrôle la PRÉSENCE et la FORME de la revue (le fond s'auto-évalue avec le corrigé).
# Lecture seule : GitLab en GET.

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E12 — Revue : la chaîne de livraison du stagiaire"
require_cmd jq

_m13_rev="$(_m13d_contenu_main "$_M13D_DOC" docs/registre/revues/revue-medinotif-lucas.md)"
check_cmd "docs/registre/revues/revue-medinotif-lucas.md sur main" test -n "$_m13_rev"
_m13_n="$(grep -cE '^[[:space:]]*(#+[[:space:]]*)?[0-9]+[.)][[:space:]]' <<<"$_m13_rev" || true)"
check_output "revue : au moins dix points numérotés (trouvés : ${_m13_n:-0})" '^([1-9][0-9]+)$' echo "${_m13_n:-0}"
# Les thèmes bloquants doivent être nommés (secrets, clé de signature, blocage des vulnérabilités).
for _m13_m in 'mot de passe|secret|jeton' 'cosign\.key|clé privée' 'allow_failure|exit-code|non bloquant' 'empreinte|digest' '0\.69'; do
  check_cmd "revue : aborde « ${_m13_m//\\/} »" grep -qiE -- "$_m13_m" <<<"$_m13_rev"
done
