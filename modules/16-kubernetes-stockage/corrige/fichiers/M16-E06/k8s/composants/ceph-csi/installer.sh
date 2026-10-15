#!/usr/bin/env bash
# =============================================================================
# composants/ceph-csi/installer.sh (plateforme/k8s) — installe ou met à jour ceph-csi.
# M16-E06 (RBD), M16-E07 (CephFS) ; mises à jour : M16-E33.
#
# Pour chaque pilote dont les values existent (values-rbd.yaml, values-cephfs.yaml) :
#   helm upgrade --install ceph-csi-<pilote> ceph-csi/ceph-csi-<pilote> --version <VERSION> \
#     --namespace ceph-csi --values values-<pilote>.yaml --wait
# puis applique les StorageClasses de classes/.
#
# Usage, sur adm01, depuis la racine de plateforme/k8s :
#   composants/ceph-csi/installer.sh            installer / mettre à jour
#   composants/ceph-csi/installer.sh --rendu    afficher les manifestes (helm template), sans rien appliquer
# Variables : CEPH_CSI_VERSION (défaut 3.18.1), KUBECONFIG (identité <MOI>).
# Préalables : espace ceph-csi (espaces/ceph-csi.yaml), contrôleur de snapshots
# (composants/snapshot-controller), dépôt Helm « ceph-csi » (https://ceph.github.io/csi-charts).
# Les Secrets des identités ne sont PAS créés ici : outils/ceph-csi-secrets.sh appliquer.
# Codes retour : 0 succès ; 1 échec ; 2 usage ou préalable manquant.
# =============================================================================
set -Eeuo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${CEPH_CSI_VERSION:-3.18.1}"
ESPACE="ceph-csi"
DEPOT="ceph-csi"
RENDU=0

usage() { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  "") ;;
  --rendu) RENDU=1 ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

erreur() { printf 'installer.sh : %s\n' "$*" >&2; }

for outil in helm kubectl; do
  command -v "$outil" >/dev/null || { erreur "$outil absent"; exit 2; }
done

# Aucun fichier ne doit garder la valeur à remplacer (clusterID = fsid de ceph-par1).
if grep -rl '<FSID>' "$ICI"/values-*.yaml "$ICI"/classes/ >/dev/null 2>&1; then
  erreur "remplace <FSID> (ceph fsid sur ceph01) dans : $(grep -rl '<FSID>' "$ICI"/values-*.yaml "$ICI"/classes/ | tr '\n' ' ')"
  exit 2
fi

if ! helm repo list -o json 2>/dev/null | grep -q "\"name\":\"$DEPOT\""; then
  erreur "dépôt Helm « $DEPOT » absent : helm repo add $DEPOT https://ceph.github.io/csi-charts"
  exit 2
fi
helm repo update "$DEPOT" >/dev/null

if ((RENDU == 0)); then
  kubectl get namespace "$ESPACE" >/dev/null 2>&1 \
    || { erreur "espace $ESPACE absent : kubectl apply -f espaces/ceph-csi.yaml"; exit 2; }
  kubectl get crd volumesnapshots.snapshot.storage.k8s.io >/dev/null 2>&1 \
    || { erreur "CRD des snapshots absentes : kubectl apply --server-side -k composants/snapshot-controller"; exit 2; }
fi

installes=0
for pilote in rbd cephfs; do
  valeurs="$ICI/values-$pilote.yaml"
  [[ -f "$valeurs" ]] || continue
  installes=$((installes + 1))
  if ((RENDU)); then
    helm template "ceph-csi-$pilote" "$DEPOT/ceph-csi-$pilote" --version "$VERSION" \
      --namespace "$ESPACE" --values "$valeurs"
    continue
  fi
  printf '→ ceph-csi-%s %s\n' "$pilote" "$VERSION"
  helm upgrade --install "ceph-csi-$pilote" "$DEPOT/ceph-csi-$pilote" --version "$VERSION" \
    --namespace "$ESPACE" --values "$valeurs" --wait --timeout 10m
done
((installes > 0)) || { erreur "aucun fichier values-*.yaml dans $ICI"; exit 2; }

if ((RENDU)); then
  cat "$ICI"/classes/*.yaml
  exit 0
fi

kubectl apply -f "$ICI/classes/"
printf 'ceph-csi en place. Secrets : outils/ceph-csi-secrets.sh appliquer && outils/ceph-csi-secrets.sh verifier\n'
