# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S05.sh — F4-S05 « Monter les composants de plateforme par GitOps » : au moins trois composants
# montés depuis leur version d'avant F4 (dont au moins une montée de MINEURE), lus dans les images en
# service ; Applications de la plateforme saines ; aucune API supprimée encore utilisée (ClusterPolicy de
# Kyverno, barmanObjectStore de CNPG) ; fiche CHG-3405 et sa mesure ; RB-342. Lecture seule.
#
# Références « avant F4 » (PLAN §6 et modules) : version exacte quand le module l'a figée, sinon
# « X.Y.999 » (seule une montée de mineure compte). WB_F4_S05_SEUIL : nombre de montées exigées (défaut 3).

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S05 — Monter les composants de plateforme par GitOps"
require_cmd kubectl curl jq

_f4_s05_seuil="${WB_F4_S05_SEUIL:-3}"
# espace | regex du dépôt d'image | version de référence | nom affiché
_f4_s05_table='argocd|/argoproj/argocd:|3.5.5|Argo CD
kyverno|/kyverno/kyverno:|1.19.2|Kyverno
cnpg-system|/cloudnative-pg/cloudnative-pg:|1.30.1|CloudNativePG
velero|/velero/velero:|1.18.4|Velero
ceph-csi|/cephcsi/cephcsi:|3.18.1|ceph-csi
cert-manager|/jetstack/cert-manager-controller:|1.21.999|cert-manager
external-secrets|/external-secrets/external-secrets:|2.13.999|External Secrets
argo-rollouts|/argoproj/argo-rollouts:|1.10.999|Argo Rollouts
keda|/kedacore/keda:|2.21.999|KEDA
vpa|/autoscaling/vpa-recommender:|1.7.1|VPA
capsule-system|/projectcapsule/capsule:|0.15.999|Capsule
falco|/falcosecurity/falco:|0.45.999|Falco
tetragon|/cilium/tetragon:|1.7.999|Tetragon
chaos-mesh|/chaos-mesh/chaos-mesh:|2.8.999|Chaos Mesh
rabbitmq-system|/rabbitmq/cluster-operator:|2.23.999|RabbitMQ Cluster Operator'

if ! _f4m_api_repond; then
  skip "composants en service" "l'API ne répond pas au compte des checks"
else
  title "Versions en service"
  _f4_s05_montes=0
  _f4_s05_mineures=0
  while IFS='|' read -r _f4_ns _f4_re _f4_ref _f4_nom; do
    _f4_v="$(_f4m_version_image "$_f4_ns" "$_f4_re" || true)"
    if [[ -z "$_f4_v" ]]; then
      skip "$_f4_nom" "image introuvable dans l'espace $_f4_ns"
      continue
    fi
    if _f4m_version_sup "$_f4_v" "$_f4_ref"; then
      _ok "$_f4_nom : $_f4_v (au-delà de la version d'avant F4)"
      _f4_s05_montes=$((_f4_s05_montes + 1))
      [[ "$(cut -d. -f1,2 <<<"$_f4_v")" != "$(cut -d. -f1,2 <<<"$_f4_ref")" ]] && _f4_s05_mineures=$((_f4_s05_mineures + 1))
    else
      printf '  [--]   %s : %s (inchangé)\n' "$_f4_nom" "$_f4_v"
    fi
  done <<<"$_f4_s05_table"
  check_cmd "au moins $_f4_s05_seuil composants montés (trouvé : $_f4_s05_montes)" test "$_f4_s05_montes" -ge "$_f4_s05_seuil"
  check_cmd "au moins une montée de mineure (trouvé : $_f4_s05_mineures)" test "$_f4_s05_mineures" -ge 1

  title "Santé et API supprimées"
  check_cmd "Applications Argo CD du projet plateforme : toutes Synced et Healthy" _f4m_kq \
    '[.items[] | select(.spec.project == "plateforme") | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")] | length == 0' \
    -n argocd applications.argoproj.io
  _f4_s05_sans_clusterpolicy() {
    local r
    r="$(kube get clusterpolicies.kyverno.io -o json 2>&1)" && { jq -e '.items | length == 0' >/dev/null 2>&1 <<<"$r"; return; }
    grep -qi "the server doesn't have a resource type" <<<"$r"
  }
  check_cmd "Kyverno : aucune ClusterPolicy (API supprimée en 1.20)" _f4_s05_sans_clusterpolicy
  check_cmd "CloudNativePG : aucun Cluster n'utilise barmanObjectStore (supprimé en 1.31)" _f4m_kq \
    '[.items[] | select(.spec.backup.barmanObjectStore != null)] | length == 0' -A clusters.postgresql.cnpg.io
  check_cmd "CloudNativePG : tous les Cluster en bonne santé" _f4m_kq \
    'all(.items[]; (.status.phase // "") | test("healthy"; "i"))' -A clusters.postgresql.cnpg.io
fi

title "Mesure et traces"
_f4m_controles_mesure CHG-3405
check_cmd "CHG-3405 : notes de version lues, CRD avant contrôleurs, charts-miroir, retour arrière" \
  _f4m_fiche_contient CHG-3405 'notes de version|release notes|changelog' 'crd' 'charts-miroir' 'retour arri'
check_cmd "RB-342 publié : monter un composant de plateforme (Argo CD ou Helmfile)" _f4m_doc runbooks '^RB-342' 'crd' 'helmfile|argo' 'revert|retour'
