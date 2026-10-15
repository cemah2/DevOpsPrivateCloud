# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E02.sh — M17-E02 « Helm 4 : installer, inspecter, monter, revenir ».
# Lecture seule : fichiers déposés dans ~/m17/e02/, objets de wb-essais, documentation dans GitLab.

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

title "M17-E02 — Helm 4 : installer, inspecter, monter, revenir"
require_cmd jq kubectl

_e02_h="$_m17d_brouillons/e02/historique.txt"
_e02_m="$_m17d_brouillons/e02/managed-fields.txt"

_e02_revisions() {
  local n
  n="$(grep -Ec '^[[:space:]]*[0-9]+[[:space:]]' "$_e02_h" 2>/dev/null)" || n=0
  (( n >= 4 ))
}
check_cmd "historique.txt : au moins quatre révisions de podinfo" _e02_revisions
check_cmd "historique.txt : un retour arrière (« Rollback to 1 »)" _m17d_fichier_contient "$_e02_h" 'Rollback to 1'
_e02_final() { grep -v '^[[:space:]]*$' "$_e02_h" 2>/dev/null | tail -n 1 | grep -q 'uninstalled'; }
check_cmd "historique.txt : dernière révision à l'état uninstalled" _e02_final
check_cmd "managed-fields.txt : gestionnaire helm" _m17d_fichier_contient "$_e02_m" 'manager:[[:space:]]*helm'
check_cmd "managed-fields.txt : opération Apply (server-side apply de Helm 4)" _m17d_fichier_contient "$_e02_m" 'operation:[[:space:]]*Apply'

_e02_reste() {
  local j
  j="$(kube get deploy,svc,pod,configmap -n wb-essais -o json 2>/dev/null)" || return 1
  jq -e '[.items[] | select((.metadata.annotations["meta.helm.sh/release-name"] // "") == "podinfo"
          or (.metadata.labels["app.kubernetes.io/name"] // "") == "podinfo")] | length == 0' >/dev/null 2>&1 <<<"$j"
}
check_cmd "wb-essais : plus aucun objet de la release podinfo" _e02_reste
check_cmd "plateforme/medisphere (main) : docs/kubernetes/packaging/fiche-helm.md" \
  _m17d_gl_existe plateforme/medisphere docs/kubernetes/packaging/fiche-helm.md
