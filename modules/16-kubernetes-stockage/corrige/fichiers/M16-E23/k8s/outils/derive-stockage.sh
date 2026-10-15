#!/usr/bin/env bash
# outils/derive-stockage.sh (plateforme/k8s) — M16-E23
# Compare le stockage du cluster au dépôt, en LECTURE seule : valeurs et versions des releases
# Helm, StorageClasses et classes d'instantanés, manifestes déclaratifs (kubectl diff).
# Sortie 0 : aucun écart ; 1 : écart(s) (listés) ; 2 : outil manquant.
#   outils/derive-stockage.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
for o in kubectl helm yq jq diff; do command -v "$o" >/dev/null || { echo "outil absent : $o" >&2; exit 2; }; done

ecarts=0
ecart() { echo "ÉCART : $*"; ecarts=$((ecarts + 1)); }
normaliser() { yq -P 'sort_keys(..)' -; }

# release espace fichier-de-valeurs version-de-chart
releases=(
  "ceph-csi-rbd ceph-csi composants/ceph-csi/values-rbd.yaml 3.18.1"
  "ceph-csi-cephfs ceph-csi composants/ceph-csi/values-cephfs.yaml 3.18.1"
  "velero velero composants/velero/values.yaml 12.2.1"
  "cnpg cnpg-system composants/cloudnative-pg/values.yaml 0.29.1"
  "plugin-barman-cloud cnpg-system composants/plugin-barman-cloud/values.yaml 0.8.1"
)
for r in "${releases[@]}"; do
  read -r nom espace valeurs version <<<"$r"
  chart="$(helm list -n "$espace" -o json | jq -r --arg n "$nom" '.[] | select(.name == $n) | .chart')"
  [[ -n "$chart" ]] || { ecart "release $nom absente de $espace"; continue; }
  [[ "$chart" == *"-$version" ]] || ecart "release $nom : chart $chart, attendu version $version"
  if ! diff -q <(helm get values "$nom" -n "$espace" -o yaml | normaliser) \
               <(normaliser < "$valeurs") >/dev/null; then
    ecart "release $nom : valeurs déployées ≠ $valeurs"
    diff <(helm get values "$nom" -n "$espace" -o yaml | normaliser) <(normaliser < "$valeurs") | head -20
  fi
done

# Manifestes déclaratifs : kubectl diff (dry-run côté serveur, rien n'est modifié).
for f in composants/ceph-csi/classes/*.yaml admission/classes-stockage.yaml \
         espaces/mediagenda-dev/30-quota-stockage.yaml espaces/mediagenda-recette/30-quota-stockage.yaml \
         composants/velero/planifications.yaml espaces/mediagenda-recette/[4-7]0-*.yaml; do
  [[ -f "$f" ]] || { ecart "$f absent du dépôt"; continue; }
  kubectl diff -f "$f" >/dev/null 2>&1
  case $? in
    0) ;;
    1) ecart "$f diffère du cluster (kubectl diff -f $f)" ;;
    *) ecart "$f : kubectl diff en erreur" ;;
  esac
done

# Ce qui a été retiré ne doit pas revenir.
for ns in rook-ceph longhorn-system; do
  kubectl get namespace "$ns" >/dev/null 2>&1 && ecart "l'espace $ns existe (retiré en M16-E14/E15)"
done

if (( ecarts == 0 )); then echo "Aucun écart entre le cluster et le dépôt."; exit 0; fi
echo "$ecarts écart(s)."; exit 1
