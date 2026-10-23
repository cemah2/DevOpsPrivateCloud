# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S03.sh — F4-S03 « Go ou no-go : la mineure suivante de Kubernetes » (RED publié) : présence et
# contenu minimal de la fiche CHG-3403 (décision écrite) et de la matrice de compatibilité.
# Lecture seule (GitLab). La justesse de l'analyse s'évalue avec le corrigé.

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S03 — Go ou no-go : la mineure suivante de Kubernetes"
require_cmd curl jq

check_cmd "fiches/CHG-3403*.md (main) : décision « go » ou « no-go » dans l'en-tête" _f4m_decision CHG-3403
check_cmd "CHG-3403 : Cilium, API dépréciées ou retirées, conditions de révision de la décision" \
  _f4m_fiche_contient CHG-3403 'cilium' 'api' 'd(é|e)pr(é|e)ci|retir' 'matrice'

_f4_s03_matrice="$(_f4m_chemin "$_f4m_projet_doc" "$_f4m_doc_dir/matrices" '^compatibilite-kubernetes-1\.[0-9]+\.md$' 2>/dev/null || true)"
_f4_s03_contenu="$(if [[ -n "$_f4_s03_matrice" ]]; then _f4m_fichier "$_f4m_projet_doc" "$_f4_s03_matrice" 2>/dev/null; fi || true)"
check_cmd "matrices/compatibilite-kubernetes-<mineure>.md présente sur main" test -n "$_f4_s03_contenu"
_f4_s03_composants() {
  local n=0 c
  for c in cilium cert-manager ceph-csi 'cloudnative-?pg|cnpg' 'argo cd|argocd' 'argo rollouts|rollouts' kyverno falco tetragon \
    keda 'vpa|vertical pod' capsule 'external secrets|external-secrets|eso' velero 'rabbitmq' 'chaos mesh|chaos-mesh' \
    'k6-operator' 'kube-prometheus|prometheus-operator' 'backstage' 'runner' 'externaldns|external-dns' 'containerd' \
    'metrics-server' 'opentelemetry'; do
    grep -Eqi -- "$c" <<<"$_f4_s03_contenu" && n=$((n + 1))
  done
  ((n >= 20))
}
check_cmd "matrice : au moins 20 des composants installés y figurent (CNI, stockage, opérateurs, GitOps, sécurité…)" _f4_s03_composants
_f4_s03_sources() { (($(grep -Ec 'https?://' <<<"$_f4_s03_contenu") >= 15)); }
check_cmd "matrice : source de chaque compatibilité : au moins 15 liens vers la documentation des projets" _f4_s03_sources
