#!/usr/bin/env bash
# plateforme/k8s — outils/inventaire-api-supprimees.sh (F4-S05, CHG-3405)
# Avant les montées de mineure du trimestre : inventaire, en LECTURE, des objets qui utilisent une API
# que la version cible supprime (annexe des versions des finaux) :
#   - Kyverno 1.20 : ClusterPolicy (kyverno.io/v1) supprimée — vérifie dans les notes de version si Policy
#     et les autres types kyverno.io/v1 le sont aussi ; MédiSphère n'utilise que les
#     politiques CEL policies.kyverno.io/v1 depuis le M26 ;
#   - CloudNativePG 1.31 : spec.backup.barmanObjectStore supprimé ; MédiSphère archive par le plugin
#     Barman Cloud depuis le M16.
# Les objets sont lus dans le CLUSTER (ce qui tourne) ; le même contrôle sur les dépôts se fait par
# kubeconform avec les schémas de la version cible (composant « validation », M29).
# Code de sortie : 0 si rien n'est trouvé, 1 sinon.
set -euo pipefail

trouve=0
echo "== Kyverno : ClusterPolicy / Policy (kyverno.io)"
for t in clusterpolicies.kyverno.io policies.kyverno.io; do
  if sortie="$(kubectl get "$t" -A -o json 2>&1)"; then
    n="$(jq '.items | length' <<<"$sortie")"
    if ((n > 0)); then
      jq -r '.items[] | "  \(.kind) \(.metadata.namespace // "-")/\(.metadata.name)"' <<<"$sortie"
      trouve=1
    else
      echo "  $t : aucun objet"
    fi
  else
    echo "  $t : type absent du cluster ($(head -n 1 <<<"$sortie"))"
  fi
done

echo "== CloudNativePG : Cluster avec spec.backup.barmanObjectStore"
kubectl get clusters.postgresql.cnpg.io -A -o json |
  jq -r '.items[] | select(.spec.backup.barmanObjectStore != null) | "  \(.metadata.namespace)/\(.metadata.name)"' |
  { if grep .; then exit 1; else echo "  aucun"; fi; } || trouve=1
echo "== CloudNativePG : ScheduledBackup et Backup sans méthode plugin (méthode intégrée par défaut)"
kubectl get scheduledbackups.postgresql.cnpg.io -A -o json |
  jq -r '.items[] | select((.spec.method // "barmanObjectStore") != "plugin") | "  \(.metadata.namespace)/\(.metadata.name) (method: \(.spec.method // "défaut"))"' |
  { if grep .; then exit 1; else echo "  aucun"; fi; } || trouve=1

exit "$trouve"
