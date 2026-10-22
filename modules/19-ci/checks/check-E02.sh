# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E02.sh — M19-E02 : préparer k8s-par1 pour la CI
# À lancer depuis adm01. Lecture seule : « qm config » sur pve01, objets Kubernetes (wb-checks, jamais
# les Secrets), sysctl lu en SSH sur les travailleurs, fichiers de main en GET sur l'API GitLab.

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E02 — Préparer k8s-par1 pour la CI"
require_cmd jq kubectl curl

# --- 1. Mémoire : Proxmox et Kubernetes -----------------------------------------------------------
_m19d_e02_noeuds="$(_m19d_kj get nodes)"
for _m19d_e02_n in "${_M19D_W[@]}"; do
  _m19d_e02_id="${_M19D_VMID[$_m19d_e02_n]:-}"
  if [[ -z "$_m19d_e02_id" ]]; then
    skip "$_m19d_e02_n : mémoire dans Proxmox" "nœud hors de la table du plan (2144-2146)"
  else
    check_output "$_m19d_e02_n (VM $_m19d_e02_id) : 10240 Mo dans Proxmox" '^memory: 10240$' _m19d_qm "$_m19d_e02_id"
  fi
  # Capacité vue par Kubernetes : au moins 9,5 Gio (10 Go moins ce que réserve le noyau).
  check_cmd "$_m19d_e02_n : capacité mémoire ≥ 9,5 Gio, Ready, non cordonné" _m19d_json "$_m19d_e02_noeuds" '
    .items[] | select(.metadata.name == $n)
    | ((.status.capacity.memory | sub("Ki$"; "") | tonumber) >= 9961472)
      and any(.status.conditions[]; .type == "Ready" and .status == "True")
      and ((.spec.unschedulable // false) == false)' --arg n "$_m19d_e02_n"
done
for _m19d_e02_n in k8s-cp01 k8s-cp02 k8s-cp03; do
  check_output "$_m19d_e02_n (VM ${_M19D_VMID[$_m19d_e02_n]}) : mémoire inchangée (4096 Mo)" '^memory: 4096$' \
    _m19d_qm "${_M19D_VMID[$_m19d_e02_n]}"
done

# --- 2. vm.max_map_count sur les travailleurs -----------------------------------------------------
for _m19d_e02_n in "${_M19D_W[@]}"; do
  check_ssh_output "$_m19d_e02_n : vm.max_map_count effectif = 524288" "$_m19d_e02_n" '^524288$' \
    'sysctl -n vm.max_map_count'
  check_ssh "$_m19d_e02_n : vm.max_map_count persistant (fichier de /etc/sysctl.d/)" "$_m19d_e02_n" \
    'grep -hsE "^[[:space:]]*vm\.max_map_count[[:space:]]*=[[:space:]]*524288[[:space:]]*$" /etc/sysctl.d/*.conf | grep -q .'
done

# --- 3. Espaces, Pod Security, quota, LimitRange, compte de service --------------------------------
_m19d_e02_ns="$(_m19d_kj get namespaces)"
check_cmd "espace gitlab-runner en Pod Security « restricted » appliqué" _m19d_json "$_m19d_e02_ns" '
  any(.items[]; .metadata.name == "gitlab-runner"
      and .metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted")'
check_cmd "espace ci-jobs : « baseline » appliqué, « restricted » en avertissement et en audit" _m19d_json "$_m19d_e02_ns" '
  any(.items[]; .metadata.name == "ci-jobs"
      and .metadata.labels["pod-security.kubernetes.io/enforce"] == "baseline"
      and .metadata.labels["pod-security.kubernetes.io/warn"] == "restricted"
      and .metadata.labels["pod-security.kubernetes.io/audit"] == "restricted")'
check_cmd "espace ci-jobs étiqueté medisphere.internal/equipe (VAP medisphere-images appliquée)" _m19d_json "$_m19d_e02_ns" '
  any(.items[]; .metadata.name == "ci-jobs" and ((.metadata.labels["medisphere.internal/equipe"] // "") != ""))'
check_cmd "espace buildkit présent, niveau de Pod Security déclaré" _m19d_json "$_m19d_e02_ns" '
  any(.items[]; .metadata.name == "buildkit" and ((.metadata.labels["pod-security.kubernetes.io/enforce"] // "") != ""))'
check_cmd "ResourceQuota quota-ci (6 CPU / 12 Gi demandés, 16 CPU / 24 Gi en limites, 20 pods)" _m19d_json \
  "$(_m19d_kj -n ci-jobs get resourcequota quota-ci)" '
  .spec.hard as $h
  | $h["requests.cpu"] == "6" and $h["requests.memory"] == "12Gi"
    and $h["limits.cpu"] == "16" and $h["limits.memory"] == "24Gi" and $h.pods == "20"'
check_cmd "LimitRange limites-ci : valeurs par défaut et maximum par conteneur (4 CPU / 4 Gi)" _m19d_json \
  "$(_m19d_kj -n ci-jobs get limitrange limites-ci)" '
  any(.spec.limits[]; .type == "Container" and .default.memory != null and .defaultRequest.memory != null
      and .max.memory == "4Gi" and (.max.cpu == "4" or .max.cpu == "4000m"))'
check_cmd "compte de service ci-jobs/ci-job sans jeton monté automatiquement" _m19d_json \
  "$(_m19d_kj -n ci-jobs get serviceaccount ci-job)" '.automountServiceAccountToken == false'
_m19d_e02_liaisons="$( { _m19d_kj get rolebindings -A; _m19d_kj get clusterrolebindings; } | jq -s '[.[].items[]?]' 2>/dev/null || true)"
check_cmd "aucune liaison RBAC ne donne de droit au compte ci-jobs/ci-job" _m19d_json "$_m19d_e02_liaisons" '
  length > 0 and ([.[] | .subjects[]? | select(.kind == "ServiceAccount" and .name == "ci-job"
                     and (.namespace // "") == "ci-jobs")] | length == 0)'

# --- 4. ClusterRole des vérifications ---------------------------------------------------------------
_m19d_e02_cr="$(_m19d_kj get clusterrole wb-checks-livraison)"
check_cmd "ClusterRole wb-checks-livraison étiquetée pour l'agrégation dans wb-checks" _m19d_json "$_m19d_e02_cr" \
  '.metadata.labels["workbook.medisphere.internal/checks"] == "true"'
check_cmd "wb-checks-livraison : lecture seule, jamais les Secrets ni « * » sur le groupe cœur" _m19d_json "$_m19d_e02_cr" '
  (.rules | length) > 0
  and all(.rules[]; all(.verbs[]; . == "get" or . == "list" or . == "watch"))
  and all(.rules[]; ((.apiGroups // []) | index("")) == null
                    or (((.resources // []) | index("secrets")) == null and ((.resources // []) | index("*")) == null))'
check_output "le compte des vérifications ne lit pas les Secrets de ci-jobs" '^no' kube auth can-i get secrets -n ci-jobs

# --- 5. Le code sur main ----------------------------------------------------------------------------
check_cmd "plateforme/infra (main) : envs/k8s porte 10240 Mo pour les travailleurs" \
  _m19d_grep_main plateforme/infra '^envs/k8s/.*\.tf$' '10240'
check_cmd "plateforme/ansible (main) : rôle k8s_travailleur avec vm.max_map_count" \
  _m19d_grep_main plateforme/ansible '^roles/k8s_travailleur/' 'max_map_count'
for _m19d_e02_motif in '^espaces/ci-jobs/' '^espaces/gitlab-runner/' '^espaces/buildkit/'; do
  check_cmd "plateforme/k8s (main) : manifestes ${_m19d_e02_motif#^}" \
    _m19d_grep_main plateforme/k8s "$_m19d_e02_motif" 'kind: *Namespace|kind: *ResourceQuota|kind: *ServiceAccount'
done
check_cmd "plateforme/k8s (main) : ClusterRole wb-checks-livraison versionnée" \
  _m19d_grep_main plateforme/k8s '^rbac/' 'name: *wb-checks-livraison'
