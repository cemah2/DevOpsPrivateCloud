# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S08.sh — F1-S08 « La couche de base et Argo CD ».
# Lecture seule : compte wb-checks (objets de Cilium, cert-manager, ceph-csi, CNPG, Velero, Argo CD ;
# jamais les Secrets), requêtes HTTPS sur les points d'entrée publiés.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S08 — La couche de base et Argo CD"
require_cmd kubectl jq curl

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi

# --- Nœuds et réseau ------------------------------------------------------------------------------
check_cmd "six nœuds Ready" _f1c_kq \
  '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length == 6' nodes
check_cmd "Cilium : agents prêts sur les six nœuds" _f1c_kq \
  '(.status.numberReady // 0) == 6 and (.status.desiredNumberScheduled // 0) == 6' -n kube-system daemonset cilium
_f1_s08_cfg="$(_f1c_kj -n kube-system configmap cilium-config)"
[[ -n "$_f1_s08_cfg" ]] || _f1_s08_cfg='{}'
_f1_s08_sans_kube_proxy() {
  jq -e '.data["kube-proxy-replacement"] == "true"' <<<"$_f1_s08_cfg" >/dev/null 2>&1 \
    && _f1c_kq '[.items[] | select(.metadata.name == "kube-proxy")] | length == 0' -n kube-system daemonsets
}
check_cmd "Cilium : remplacement de kube-proxy actif, aucun DaemonSet kube-proxy" _f1_s08_sans_kube_proxy
check_cmd "Cilium : chiffrement WireGuard et pare-feu d'hôte activés" \
  jq -e '.data["enable-wireguard"] == "true" and .data["enable-host-firewall"] == "true"' <<<"$_f1_s08_cfg"
check_cmd "pool LB IPAM lb-par1 présent" _f1c_kq '.metadata.name == "lb-par1"' ciliumloadbalancerippools.cilium.io lb-par1
if _f1c_lit ciliumbgpnodeconfigs.cilium.io; then
  check_cmd "BGP : deux sessions établies (10.10.40.2 et 10.10.40.3) pour chacun des six nœuds" _f1c_kq '
    (.items | length == 6) and all(.items[];
      ([.status.bgpInstances[]?.peers[]? | select((.peeringState // "" | ascii_downcase) == "established") | .peerAddress] | sort | unique)
      == ["10.10.40.2", "10.10.40.3"])' ciliumbgpnodeconfigs.cilium.io
else
  skip "sessions BGP" "le compte des checks ne lit pas ciliumbgpnodeconfigs"
fi
check_cmd "Gateway gw-par1 programmée sur $_f1c_gw_ip" _f1c_kq \
  'any(.status.conditions[]?; .type == "Programmed" and .status == "True") and any(.status.addresses[]?; .value == "'"$_f1c_gw_ip"'")' \
  -n passerelles gateways.gateway.networking.k8s.io gw-par1
check_cmd "Hubble relay prêt" _f1c_deploiement_pret kube-system hubble-relay

# --- Certificats et DNS -------------------------------------------------------------------------------
for _f1_s08_ns in cert-manager external-dns; do
  check_cmd "espace $_f1_s08_ns : charges prêtes" _f1c_espace_pret "$_f1_s08_ns"
done
check_cmd "ClusterIssuer step-ca-acme prêt" _f1c_kq 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
  clusterissuers.cert-manager.io step-ca-acme
check_cmd "certificat apps-joker de la Gateway prêt" _f1c_kq \
  'any(.items[]; .metadata.name == "apps-joker" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
  certificates.cert-manager.io -A
check_http "Argo CD publié : https://argocd.$_f1c_zone_apps répond (TLS vérifié)" "https://argocd.$_f1c_zone_apps/healthz" 200

# --- Stockage, données, sauvegarde, métriques ------------------------------------------------------------
for _f1_s08_ns in ceph-csi cnpg-system velero; do
  check_cmd "espace $_f1_s08_ns : charges prêtes" _f1c_espace_pret "$_f1_s08_ns"
done
check_cmd "contrôleur de snapshots prêt (kube-system/snapshot-controller)" _f1c_deploiement_pret kube-system snapshot-controller
_f1_s08_sc="$(_f1c_kj storageclasses)"
[[ -n "$_f1_s08_sc" ]] || _f1_s08_sc='{"items":[]}'
for _f1_s08_c in ceph-rbd ceph-rbd-retain ceph-rbd-chiffre cephfs; do
  check_cmd "StorageClass $_f1_s08_c présente" jq -e --arg c "$_f1_s08_c" 'any(.items[]; .metadata.name == $c)' <<<"$_f1_s08_sc"
done
check_cmd "ceph-rbd est la seule StorageClass par défaut" jq -e '
  [.items[] | select((.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "") == "true") | .metadata.name] == ["ceph-rbd"]' \
  <<<"$_f1_s08_sc"
check_cmd "Velero : emplacement s3-01 Available" _f1c_kq '.status.phase == "Available"' -n velero backupstoragelocations.velero.io s3-01
if _f1c_peut get apiservices.apiregistration.k8s.io; then
  check_cmd "API metrics.k8s.io disponible (metrics-server lit les kubelets)" _f1c_kq \
    'any(.status.conditions[]?; .type == "Available" and .status == "True")' apiservices v1beta1.metrics.k8s.io
else
  check_cmd "metrics-server prêt (kube-system/metrics-server)" _f1c_deploiement_pret kube-system metrics-server
fi

# --- CI et Argo CD ------------------------------------------------------------------------------------------
for _f1_s08_ns in gitlab-runner buildkit gitlab-agent argocd; do
  check_cmd "espace $_f1_s08_ns : charges prêtes" _f1c_espace_pret "$_f1_s08_ns"
done
check_cmd "deux gestionnaires de runners dans gitlab-runner (k8s-par1 et k8s-par1-protege)" _f1c_kq \
  '[.items[] | select((.status.availableReplicas // 0) >= 1)] | length >= 2' -n gitlab-runner deployments

# --- Pare-feu d'hôte -----------------------------------------------------------------------------------------
for _f1_s08_p in hote-commun hote-plan-controle hote-travailleurs; do
  check_cmd "politique d'hôte $_f1_s08_p présente" _f1c_kq '.metadata.name != null' ciliumclusterwidenetworkpolicies.cilium.io "$_f1_s08_p"
done
check_cmd "les six nœuds portent medisphere.internal/pare-feu-hote=oui" _f1c_kq \
  '[.items[] | select(.metadata.labels["medisphere.internal/pare-feu-hote"] == "oui")] | length == 6' nodes

# --- Aucune base née vide ----------------------------------------------------------------------------------------
if _f1c_lit clusters.postgresql.cnpg.io; then
  check_cmd "aucun Cluster CNPG amorcé par initdb dans mediagenda-recette, mediagenda-prod ni portail" _f1c_kq '
    [.items[] | select(.metadata.namespace | IN("mediagenda-recette", "mediagenda-prod", "portail"))
              | select(.spec.bootstrap.recovery == null)] | length == 0' clusters.postgresql.cnpg.io -A
else
  skip "bases CNPG" "CRD absente ou illisible par le compte des checks"
fi
