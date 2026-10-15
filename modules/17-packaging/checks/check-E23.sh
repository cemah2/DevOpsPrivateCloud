# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E23.sh — M17-E23 « Sous le capot » : release capot-cm sous le pilote configmap (≥ 2 révisions,
# la dernière deployed), release capot désinstallée, outil helm-release.sh sur main. Lecture seule.

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E23 — Sous le capot de Helm"
require_cmd jq kubectl

_e23_cm="$(kube get configmap -n wb-essais -l owner=helm,name=capot-cm -o json 2>/dev/null)" || _e23_cm=""
check_cmd "wb-essais : au moins deux révisions de capot-cm stockées en ConfigMap" \
  _m17p_jq "$_e23_cm" '[.items[] | select(.metadata.name | startswith("sh.helm.release.v1.capot-cm.v"))] | length >= 2'
check_cmd "wb-essais : la dernière révision de capot-cm est deployed" \
  _m17p_jq "$_e23_cm" '[.items[] | {v: (.metadata.labels.version | tonumber), s: .metadata.labels.status}] | max_by(.v) | .s == "deployed"'
_e23_sec() { [[ -z "$(_m17p_kadmin get secret -n wb-essais -l owner=helm,name=capot -o name)" ]]; }
check_cmd "wb-essais : release capot désinstallée (aucun Secret sh.helm.release.v1.capot.*)" _e23_sec

_e23_outil="$(_m17p_gl_fichier plateforme/k8s outils/helm-release.sh)" || _e23_outil=""
check_cmd "plateforme/k8s : outils/helm-release.sh sur main" test -n "$_e23_outil"
if [[ -n "$_e23_outil" ]]; then
  check_cmd "helm-release.sh : syntaxe bash valide" bash -n <(printf '%s\n' "$_e23_outil")
  if command -v shellcheck >/dev/null 2>&1; then
    check_cmd "helm-release.sh : ShellCheck propre" shellcheck -s bash - <<<"$_e23_outil"
  else
    skip "helm-release.sh : ShellCheck" "shellcheck absent de ce poste"
  fi
  check_cmd "helm-release.sh : gère les pilotes secret et configmap" grep -qi 'configmap' <<<"$_e23_outil"
fi
