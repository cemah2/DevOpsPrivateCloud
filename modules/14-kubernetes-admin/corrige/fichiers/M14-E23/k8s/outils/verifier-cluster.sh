#!/usr/bin/env bash
# « test && ok … || pasok … » : ok() renvoie toujours 0, pasok() n'est atteint que si le test échoue.
# shellcheck disable=SC2015
# plateforme/k8s — outils/verifier-cluster.sh (M14-E23)
# Le cluster est-il conforme au dépôt ? Lecture seule. À lancer depuis la racine du dépôt (task verifier).
#   - nœuds attendus (cluster/noeuds.yaml) présents, Ready, ordonnançables ;
#   - étiquettes et taints MédiSphère conformes à cluster/noeuds.yaml ;
#   - paramètres principaux de kubeadm (ConfigMap kube-system/kubeadm-config) = cluster/kubeadm-config.yaml ;
#   - composants : Cilium et metrics-server disponibles ;
#   - aucune dérive (outils/derive.sh).
# Code de sortie : 0 conforme, 1 sinon.
set -uo pipefail

contexte="${1:-k8s-par1}"
k() { kubectl --context "$contexte" "$@"; }
ko=0
ok()   { printf '  [OK]  %s\n' "$1"; }
pasok() { printf '  [KO]  %s\n' "$1"; ko=1; }

noeuds_json="$(k get nodes -o json)" || { echo "API injoignable" >&2; exit 1; }

echo "== Nœuds et étiquettes =="
for n in $(yq -r '.noeuds | keys | .[]' cluster/noeuds.yaml); do
  nj="$(jq --arg n "$n" '.items[] | select(.metadata.name == $n)' <<<"$noeuds_json")"
  if [[ -z "$nj" ]]; then pasok "$n absent du cluster"; continue; fi
  jq -e '.status.conditions[] | select(.type == "Ready") | .status == "True"' <<<"$nj" >/dev/null \
    && ok "$n Ready" || pasok "$n pas Ready"
  jq -e '.spec.unschedulable != true' <<<"$nj" >/dev/null || pasok "$n SchedulingDisabled"
  while IFS='=' read -r cle val; do
    [[ -z "$cle" ]] && continue
    [[ "$(jq -r --arg c "$cle" '.metadata.labels[$c] // ""' <<<"$nj")" == "$val" ]] \
      && ok "$n $cle=$val" || pasok "$n : étiquette $cle différente de « $val »"
  done < <(N="$n" yq -r '.noeuds[strenv(N)].etiquettes // {} | to_entries | .[] | .key + "=" + .value' cluster/noeuds.yaml)
  while IFS='|' read -r cle val effet; do
    [[ -z "$cle" ]] && continue
    jq -e --arg c "$cle" --arg v "$val" --arg e "$effet" \
      'any(.spec.taints[]?; .key == $c and .value == $v and .effect == $e)' <<<"$nj" >/dev/null \
      && ok "$n taint $cle=$val:$effet" || pasok "$n : taint $cle=$val:$effet absente"
  done < <(N="$n" yq -r '.noeuds[strenv(N)].taints // [] | .[] | .cle + "|" + .valeur + "|" + .effet' cluster/noeuds.yaml)
done

echo "== Configuration kubeadm (dépôt / cluster) =="
cluster_cfg="$(k get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}')"
for champ in .kubernetesVersion .controlPlaneEndpoint .networking.podSubnet .networking.serviceSubnet .clusterName; do
  depot="$(yq ea -N "select(.kind == \"ClusterConfiguration\") | $champ" cluster/kubeadm-config.yaml)"
  vivant="$(yq -N "$champ" <<<"$cluster_cfg")"
  [[ "$depot" == "$vivant" ]] && ok "$champ = $depot" || pasok "$champ : dépôt « $depot », cluster « $vivant »"
done

echo "== Composants =="
k -n kube-system rollout status ds/cilium --timeout=10s >/dev/null 2>&1 && ok "Cilium (DaemonSet) à jour" || pasok "Cilium incomplet"
[[ "$(k get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" == True ]] \
  && ok "metrics-server disponible" || pasok "API metrics.k8s.io indisponible"

echo "== Dérive =="
if outils/derive.sh "$contexte" plateforme-k8s espaces rbac admission ordonnancement >/dev/null 2>&1; then
  ok "aucune dérive"
else
  pasok "dérive (détail : task derive)"
fi

((ko)) && { echo "Cluster NON conforme."; exit 1; }
echo "Cluster conforme au dépôt."
