# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E09.sh — M28-E09 : vCluster : un cluster virtuel pour une équipe, puis retrait
# Ne passe qu'une fois le comparatif ÉCRIT et l'essai RETIRÉ (avant l'exercice, le document manque).
# Lecture seule : document (GitLab, GET) ; Applications, espaces, pods, PVC, ClusterRoles, Tenant (kube).

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E09 — vCluster : un cluster virtuel pour une équipe, puis retrait"
require_cmd jq kubectl curl

check_cmd "plateforme/medisphere : comparatif-capsule-vcluster.md (API, CRD, coût, sécurité, décision)" \
  _m28d_doc docs/plateforme-dev/comparatif-capsule-vcluster.md 'vCluster' 'Capsule' 'CRD' 'Pod Security|PSA' 'co[uû]t|mémoire' 'Décision'
check_cmd "le comparatif constate ce que l'hôte impose aux pods synchronisés" \
  _m28d_doc docs/plateforme-dev/comparatif-capsule-vcluster.md 'synchronis' 'quota'
check_cmd "Application vc-essai retirée d'Argo CD" _m28d_absent applications.argoproj.io vc-essai argocd
check_cmd "espace medidoc-vc-essai supprimé" _m28d_absent namespaces medidoc-vc-essai
check_cmd "aucun plan de contrôle de vCluster dans le cluster (pods app=vcluster)" _m28d_kq \
  '.items | length == 0' pods -A -l app=vcluster
check_cmd "aucun pod synchronisé par un vCluster (étiquette vcluster.loft.sh/managed-by)" _m28d_kq \
  '.items | length == 0' pods -A -l vcluster.loft.sh/managed-by
check_cmd "aucune ClusterRole laissée par le chart (vc-vc-essai-…)" _m28d_kq \
  '[.items[].metadata.name | select(startswith("vc-vc-essai"))] | length == 0' clusterroles.rbac.authorization.k8s.io
check_cmd "le locataire medidoc ne compte plus l'espace d'essai" _m28d_kq \
  '(.status.namespaces // []) | index("medidoc-vc-essai") == null' tenants.capsule.clastix.io medidoc
