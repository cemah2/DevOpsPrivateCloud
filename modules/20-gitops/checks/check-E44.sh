# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M20-E44 « Sous le capot : du commit à l'objet » : livrable
# docs/livraison/gitops/sous-le-capot.md commité et complet (chaîne mesurée, repo-server et son
# cache, Redis, contrôleur, comparaison, annotation de suivi réelle), journaux d'Argo CD revenus au
# niveau info, aucune dérive laissée sur la release argocd. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E44 — Sous le capot : du commit à l'objet"
require_cmd jq kubectl git

_m20_e44_doc="docs/livraison/gitops/sous-le-capot.md"
check_cmd "livrable $_m20_e44_doc commité" _m20x_doc_commite "$_m20_e44_doc"
check_cmd "livrable : chronologie mesurée du commit au pod (horodatages)" _m20x_doc_contient "$_m20_e44_doc" '^#+ .*(chronologie|du commit)'
check_cmd "livrable : horodatages relevés (hh:mm:ss)" _m20x_doc_contient "$_m20_e44_doc" '[0-9]{2}:[0-9]{2}:[0-9]{2}'
check_cmd "livrable : copies de travail du repo-server relevées (/tmp/_argocd-repo/…)" _m20x_doc_contient "$_m20_e44_doc" '_argocd-repo'
check_cmd "livrable : clés de cache relevées dans Redis (mfst|, git-refs|…)" _m20x_doc_contient "$_m20_e44_doc" '(mfst|git-refs|appdetails|revisionmetadata)\|'
check_cmd "livrable : réconciliation lue dans le journal du contrôleur (« Reconciliation completed »)" _m20x_doc_contient "$_m20_e44_doc" 'Reconciliation completed'
check_cmd "livrable : annotation de suivi réelle d'un objet de dev" _m20x_doc_contient "$_m20_e44_doc" \
  'mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda'
check_cmd "livrable : rendu par « argocd app manifests » comparé au rendu local" _m20x_doc_contient "$_m20_e44_doc" 'argocd app manifests'
check_cmd "livrable : stratégie de comparaison établie par sa source (annotation compare-options, paramètre du contrôleur)" \
  _m20x_doc_contient "$_m20_e44_doc" '(compare-options|ServerSideDiff=(true|false)|controller\.diff\.server\.side)'
check_cmd "plateforme/outils : outil chronometrer-livraison.sh présent" _m20x_fichier_present plateforme/outils chronometrer-livraison.sh
if _m20x_argo_lisible; then
  check_cmd "argocd-cmd-params-cm : journaux du contrôleur et du repo-server revenus hors debug" \
    _m20x_kq '((.data["controller.log.level"] // "info") != "debug") and ((.data["reposerver.log.level"] // "info") != "debug")' \
    -n "$_m20x_ns" configmap argocd-cmd-params-cm
  check_cmd "repo-server et serveur Argo CD sans conteneur supplémentaire ni outil de débogage laissé" \
    _m20x_kq '[.items[] | select(.spec.ephemeralContainers != null)] | length == 0' -n "$_m20x_ns" pods
else
  skip "configuration d'Argo CD" "le compte des checks ne lit pas l'espace argocd"
fi
