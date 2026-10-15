# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M14-E34 « Examen blanc d'administration » (à lancer à T1, AVANT le nettoyage)
# Lecture seule : objets de l'espace wb-examen, nœuds, PriorityClass, CiliumNode (API, compte
# wb-checks), instantané /var/backups/etcd/examen-blanc.db sur k8s-cp01 (stat et etcdutl snapshot
# status), état des membres etcd, fichier ~/examen-blanc/reponses.txt d'adm01.
# Chaque tâche vaut ses points si TOUS ses contrôles passent ; l'exercice est validé à 70 points.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E34 — Examen blanc d'administration"
require_cmd kubectl jq ssh
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_M14_E34_NS=wb-examen
_M14_E34_IMAGE='registry.par1.medisphere.internal/medisphere/mediagenda-api:'
_M14_E34_REP="$HOME/examen-blanc/reponses.txt"
_m14_e34_score=0
_m14_e34_max=0

# _m14_e34_tache NUM POIDS TITRE CONTRÔLE… — chaque CONTRÔLE est le nom d'une fonction ; la tâche
# rapporte POIDS si toutes réussissent. Affichage propre à l'examen (ne compte pas dans le bilan).
_m14_e34_tache() {
  local num="$1" poids="$2" titre="$3" f echec=""
  shift 3
  _m14_e34_max=$((_m14_e34_max + poids))
  for f in "$@"; do
    if ! "$f" >/dev/null 2>&1; then echec="${echec:+$echec, }${f#_m14_e34_}"; fi
  done
  if [[ -z "$echec" ]]; then
    _m14_e34_score=$((_m14_e34_score + poids))
    printf '  [%2d/%2d] tâche %2d — %s\n' "$poids" "$poids" "$num" "$titre"
  else
    printf '  [ 0/%2d] tâche %2d — %s (en défaut : %s)\n' "$poids" "$num" "$titre" "$echec"
  fi
}

# Lectures (une fois).
_m14_e34_ns="$(_m14p_json get namespace "$_M14_E34_NS")"
_m14_e34_quota="$(_m14p_json -n "$_M14_E34_NS" get resourcequota quota-examen)"
_m14_e34_lr="$(_m14p_json -n "$_M14_E34_NS" get limitrange limites-examen)"
_m14_e34_cm="$(_m14p_json -n "$_M14_E34_NS" get configmap api-examen-config)"
_m14_e34_api="$(_m14p_json -n "$_M14_E34_NS" get deployment api-examen)"
_m14_e34_pods_api="$(_m14p_json -n "$_M14_E34_NS" get pods -l app=api-examen)"
_m14_e34_noeuds="$(_m14p_json get nodes)"
_m14_e34_svc="$(_m14p_json -n "$_M14_E34_NS" get service api-examen)"
_m14_e34_eps="$(_m14p_json -n "$_M14_E34_NS" get endpointslices)"
_m14_e34_pdb="$(_m14p_json -n "$_M14_E34_NS" get pdb api-examen)"
_m14_e34_sa="$(_m14p_json -n "$_M14_E34_NS" get serviceaccount lecteur-examen)"
_m14_e34_role="$(_m14p_json -n "$_M14_E34_NS" get role lecture-pods)"
_m14_e34_rb="$(_m14p_json -n "$_M14_E34_NS" get rolebinding lecteur-examen)"
_m14_e34_cj="$(_m14p_json -n "$_M14_E34_NS" get cronjob purge-examen)"
_m14_e34_rdv="$(_m14p_json -n "$_M14_E34_NS" get deployment rdv-examen)"
_m14_e34_frontal="$(_m14p_json -n "$_M14_E34_NS" get deployment frontal-examen)"
_m14_e34_pods="$(_m14p_json -n "$_M14_E34_NS" get pods)"
_m14_e34_pc="$(_m14p_json get priorityclass examen-haute)"
_m14_e34_cn="$(_m14p_json get ciliumnode k8s-w02)"

# _m14_e34_rep CLÉ — valeur de CLÉ dans reponses.txt.
_m14_e34_rep() { [[ -r "$_M14_E34_REP" ]] && sed -nE "s/^$1=(.*)\$/\\1/p" "$_M14_E34_REP" | tail -1 | tr -d '[:space:]'; }
# _m14_e34_eps_prets SERVICE N — le Service a exactement N points d'accès prêts.
_m14_e34_eps_prets() {
  _m14p_jq "$_m14_e34_eps" "[.items[] | select(.metadata.labels[\"kubernetes.io/service-name\"] == \"$1\")
    | .endpoints[]? | select(.conditions.ready == true)] | length == $2"
}
# Image MédiAgenda explicite (jamais latest) pour tous les conteneurs d'un gabarit de pod.
_M14_E34_IMG_OK="all(.containers[]; (.image | startswith(\"$_M14_E34_IMAGE\")) and (.image | endswith(\":latest\") | not))"

# --- Tâche 1 ---
_m14_e34_t1_etiquettes() { _m14p_jq "$_m14_e34_ns" '.metadata.labels.examen == "blanc" and .metadata.labels["pod-security.kubernetes.io/enforce"] == "baseline"'; }
# --- Tâche 2 ---
_m14_e34_t2_quota() {
  _m14p_jq "$_m14_e34_quota" '.spec.hard as $h | $h.pods == "15" and ($h["requests.cpu"] | IN("2", "2000m"))
    and ($h["requests.memory"] | IN("4Gi", "4096Mi")) and ($h["limits.memory"] | IN("6Gi", "6144Mi"))'
}
_m14_e34_t2_limites() {
  _m14p_jq "$_m14_e34_lr" 'any(.spec.limits[]; .type == "Container" and .defaultRequest.cpu == "100m"
    and .defaultRequest.memory == "128Mi" and .default.memory == "256Mi")'
}
# --- Tâche 3 ---
_m14_e34_t3_configmap() {
  _m14p_jq "$_m14_e34_cm" '.data.MEDIAGENDA_DB_URL == "postgresql://examen@base.wb-examen.svc:5432/examen"
    and .data.MEDIAGENDA_VALKEY_URL == "redis://cache.wb-examen.svc:6379/0" and .data.MEDIAGENDA_LOG_LEVEL == "INFO"'
}
_m14_e34_t3_deploiement() {
  _m14p_jq "$_m14_e34_api" ".spec.replicas == 3 and .spec.template.metadata.labels.app == \"api-examen\"
    and (.spec.template.spec | $_M14_E34_IMG_OK)"
}
_m14_e34_t3_environnement() {
  _m14p_jq "$_m14_e34_api" '.spec.template.spec.containers[0] as $c
    | any($c.envFrom[]?; .configMapRef.name == "api-examen-config")
      or ([$c.env[]? | select(.valueFrom.configMapKeyRef.name == "api-examen-config") | .name]
          | (index("MEDIAGENDA_DB_URL") and index("MEDIAGENDA_VALKEY_URL") and index("MEDIAGENDA_LOG_LEVEL")))'
}
_m14_e34_t3_sondes() {
  _m14p_jq "$_m14_e34_api" '.spec.template.spec.containers[0] as $c
    | ([$c.ports[]? | select(.containerPort == 8000) | .name] + [8000]) as $p
    | all($c.livenessProbe, $c.readinessProbe; .httpGet.path == "/sante" and (.httpGet.port as $x | $p | index($x)))'
}
_m14_e34_t3_ressources() {
  _m14p_jq "$_m14_e34_api" '.spec.template.spec.containers[0].resources as $r
    | $r.requests.cpu == "100m" and $r.requests.memory == "128Mi" and $r.limits.memory == "256Mi"'
}
_m14_e34_t3_prets() { _m14p_jq "$_m14_e34_api" '(.status.readyReplicas // 0) == 3'; }
# --- Tâche 4 ---
_m14_e34_t4_contrainte() {
  _m14p_jq "$_m14_e34_api" 'any(.spec.template.spec.topologySpreadConstraints[]?;
    .topologyKey == "topology.kubernetes.io/zone" and .maxSkew == 1 and .whenUnsatisfiable == "DoNotSchedule"
    and .nodeTaintsPolicy == "Honor")'
}
# Trois pods en cours sur au moins deux zones, écart d'au plus 1 entre les zones utilisées.
_m14_e34_t4_zones() {
  jq -e --argjson n "$_m14_e34_noeuds" '[.items[] | select(.status.phase == "Running") | .spec.nodeName as $x
      | $n.items[] | select(.metadata.name == $x) | .metadata.labels["topology.kubernetes.io/zone"]]
    | (length == 3) and all(. != null) and (group_by(.) | map(length) | (length >= 2) and (max - min <= 1))' \
    <<<"$_m14_e34_pods_api" >/dev/null
}
# --- Tâche 5 ---
_m14_e34_t5_service() {
  _m14p_jq "$_m14_e34_svc" '.spec.type == "ClusterIP" and .spec.selector.app == "api-examen"
    and any(.spec.ports[]; .port == 80 and (.targetPort == 8000 or .targetPort == "http"))'
}
_m14_e34_t5_points() { _m14_e34_eps_prets api-examen 3; }
# --- Tâche 6 ---
_m14_e34_t6_pdb() {
  _m14p_jq "$_m14_e34_pdb" '(.spec.minAvailable == 2 or .spec.minAvailable == "2") and .spec.selector.matchLabels.app == "api-examen"'
}
# --- Tâche 7 ---
_m14_e34_t7_compte() { _m14p_jq "$_m14_e34_sa" '.metadata.name == "lecteur-examen"'; }
_m14_e34_t7_role() {
  _m14p_jq "$_m14_e34_role" '([.rules[] | .resources[]] | unique) == ["pods", "pods/log"]
    and all(.rules[]; (.apiGroups == [""]) and (.verbs | all(IN("get", "list", "watch"))))
    and ([.rules[] | .verbs[]] | unique) == ["get", "list", "watch"]'
}
_m14_e34_t7_liaison() {
  _m14p_jq "$_m14_e34_rb" '.roleRef.kind == "Role" and .roleRef.name == "lecture-pods"
    and any(.subjects[]; .kind == "ServiceAccount" and .name == "lecteur-examen" and (.namespace // "wb-examen") == "wb-examen")'
}
# --- Tâche 8 ---
_m14_e34_t8_planification() {
  _m14p_jq "$_m14_e34_cj" '(.spec.schedule | gsub("\\s+"; " ")) == "*/15 * * * *" and .spec.timeZone == "Europe/Paris"
    and .spec.concurrencyPolicy == "Forbid" and .spec.successfulJobsHistoryLimit == 2 and .spec.failedJobsHistoryLimit == 1'
}
_m14_e34_t8_gabarit() {
  _m14p_jq "$_m14_e34_cj" ".spec.jobTemplate.spec.template.spec as \$s | \$s.restartPolicy == \"Never\" and (\$s | $_M14_E34_IMG_OK)
    and ((\$s.containers[0].command // []) + (\$s.containers[0].args // []) | join(\" \") | test(\"python.*print\\\\('purge'\\\\)\"))"
}
# --- Tâche 9 ---
_m14_e34_t9_deploiement() { _m14p_jq "$_m14_e34_rdv" '.spec.replicas == 2 and (.status.readyReplicas // 0) == 2'; }
_m14_e34_t9_service() { _m14_e34_eps_prets rdv-examen 2; }
# --- Tâche 10 ---
_m14_e34_t10_etiquette() {
  _m14p_jq "$_m14_e34_noeuds" 'any(.items[]; .metadata.name == "k8s-w01" and .metadata.labels["examen.medisphere.internal/frontal"] == "oui")'
}
_m14_e34_t10_affinite() {
  _m14p_jq "$_m14_e34_frontal" '.spec.template.spec as $s
    | any($s.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?;
        .key == "examen.medisphere.internal/frontal")
      and (($s.nodeSelector // {}) | has("examen.medisphere.internal/frontal") | not)'
}
_m14_e34_t10_place() {
  _m14p_jq "$_m14_e34_pods" 'any(.items[]; (.metadata.labels.app // "") == "frontal-examen" and .status.phase == "Running" and .spec.nodeName == "k8s-w01")'
}
# --- Tâche 11 ---
_m14_e34_t11_taint() {
  _m14p_jq "$_m14_e34_noeuds" 'any(.items[]; .metadata.name == "k8s-w03"
    and any(.spec.taints[]?; .key == "examen" and .value == "maintenance" and .effect == "NoSchedule"))'
}
_m14_e34_t11_pod() {
  _m14p_jq "$_m14_e34_pods" 'any(.items[]; .metadata.name == "outil-examen" and .status.phase == "Running" and .spec.nodeName == "k8s-w03"
    and any(.spec.tolerations[]?; .key == "examen" and (.effect // "NoSchedule") == "NoSchedule"))'
}
# --- Tâche 12 ---
_m14_e34_inst="$(remote k8s-cp01 'sudo -n find /var/backups/etcd/examen-blanc.db -mmin -180 2>/dev/null | grep -q . && sudo -n /usr/local/bin/etcdutl snapshot status /var/backups/etcd/examen-blanc.db -w json' 2>/dev/null || true)"
_m14_e34_t12_instantane() { jq -e '.revision > 0' >/dev/null 2>&1 <<<"$_m14_e34_inst"; }
_m14_e34_t12_reponse() {
  local r
  r="$(jq -r '.revision' <<<"$_m14_e34_inst" 2>/dev/null)" || return 1
  [[ -n "$r" && "$(_m14_e34_rep revision_instantane)" == "$r" ]]
}
# --- Tâche 13 ---
_m14_e34_table="$(_m14p_etcdctl k8s-cp01 'endpoint status --cluster -w table' || true)"
# _m14_e34_colonne NOM — valeurs de la colonne NOM du tableau etcdctl, une par membre (« point_d_accès valeur »).
_m14_e34_colonne() {
  awk -F'|' -v nom="$1" '
    /ENDPOINT/ { for (i = 1; i <= NF; i++) { c = $i; gsub(/^ +| +$/, "", c); if (c == nom) col = i; if (c == "ENDPOINT") ep = i } ; next }
    col && NF > col { e = $ep; v = $col; gsub(/^ +| +$/, "", e); gsub(/^ +| +$/, "", v); print e, v }' <<<"$_m14_e34_table"
}
_m14_e34_t13_version() {
  local v
  v="$(_m14p_version_etcd_cluster)"
  [[ -n "$v" && "$(_m14_e34_rep version_etcd)" == "$v" ]]
}
_m14_e34_t13_leader() {
  local ip n
  ip="$(_m14_e34_colonne 'IS LEADER' | awk '$2 == "true" { print $1 }' | sed -E 's#https?://([^:]+):.*#\1#' | head -1)"
  [[ -n "$ip" ]] || return 1
  for n in "${!_M14P_IP[@]}"; do
    if [[ "${_M14P_IP[$n]}" == "$ip" ]]; then [[ "$(_m14_e34_rep leader_etcd)" == "$n" ]]; return; fi
  done
  return 1
}
_m14_e34_t13_cidr() {
  local r
  r="$(_m14_e34_rep cidr_pods_k8s-w02)"
  [[ -n "$r" ]] && jq -e --arg r "$r" '(.spec.ipam.podCIDRs // []) | index($r) != null' >/dev/null 2>&1 <<<"$_m14_e34_cn"
}
# --- Tâche 14 ---
_m14_e34_t14_classe() {
  _m14p_jq "$_m14_e34_pc" '.value == 100000 and (.globalDefault // false) == false and .preemptionPolicy == "Never"'
}
_m14_e34_t14_utilisee() {
  _m14p_jq "$_m14_e34_api" '.spec.template.spec.priorityClassName == "examen-haute" and (.status.readyReplicas // 0) == 3'
}

title "Tâches"
_m14_e34_tache 1 4 "espace wb-examen" _m14_e34_t1_etiquettes
_m14_e34_tache 2 6 "quota et LimitRange" _m14_e34_t2_quota _m14_e34_t2_limites
_m14_e34_tache 3 10 "ConfigMap et Deployment api-examen" _m14_e34_t3_configmap _m14_e34_t3_deploiement \
  _m14_e34_t3_environnement _m14_e34_t3_sondes _m14_e34_t3_ressources _m14_e34_t3_prets
_m14_e34_tache 4 6 "répartition entre les zones" _m14_e34_t4_contrainte _m14_e34_t4_zones
_m14_e34_tache 5 5 "Service api-examen" _m14_e34_t5_service _m14_e34_t5_points
_m14_e34_tache 6 5 "PodDisruptionBudget" _m14_e34_t6_pdb
_m14_e34_tache 7 8 "compte de service, Role, RoleBinding" _m14_e34_t7_compte _m14_e34_t7_role _m14_e34_t7_liaison
_m14_e34_tache 8 6 "CronJob purge-examen" _m14_e34_t8_planification _m14_e34_t8_gabarit
_m14_e34_tache 9 10 "dépannage de rdv-examen" _m14_e34_t9_deploiement _m14_e34_t9_service
_m14_e34_tache 10 6 "affinité de nœud" _m14_e34_t10_etiquette _m14_e34_t10_affinite _m14_e34_t10_place
_m14_e34_tache 11 8 "taint et tolérances" _m14_e34_t11_taint _m14_e34_t11_pod
_m14_e34_tache 12 10 "instantané etcd" _m14_e34_t12_instantane _m14_e34_t12_reponse
_m14_e34_tache 13 8 "réponses etcd et Cilium" _m14_e34_t13_version _m14_e34_t13_leader _m14_e34_t13_cidr
_m14_e34_tache 14 8 "PriorityClass" _m14_e34_t14_classe _m14_e34_t14_utilisee

echo
printf '  Score : %d / %d\n' "$_m14_e34_score" "$_m14_e34_max"
title "Résultat"
check_output "au moins 70 points sur 100 (score : $_m14_e34_score)" '^ok$' \
  bash -c '(( $1 >= 70 )) && echo ok' _ "$_m14_e34_score"
check_cmd "le fichier de réponses existe ($_M14_E34_REP)" test -r "$_M14_E34_REP"
