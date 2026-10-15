# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M14-E46 « Mini-projet : Kubernetes MédiSphère v1 »
# Contrôle global de la livraison k8s-v1 (depuis adm01). Lecture seule : « kube » (compte wb-checks,
# dont SubjectAccessReview, non persistée), SSH + sudo -n en lecture sur les nœuds, pvesh/qm en
# lecture sur pve01, NetBox et GitLab en GET, stockage objet en liste (identité etcd-k8s), PBS en
# lecture. Les contrôles détaillés restent dans leurs exercices (lab/bin/check 14 XX). 3 à 5 minutes.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"
# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E46 — Kubernetes MédiSphère v1 : contrôle global"
require_cmd jq kubectl ssh curl openssl aws dig
check_cmd "l'API répond par la VIP au compte des checks (/readyz)" _m14p_joignable

_m14_e46_noeuds="$(_m14p_json get nodes)"

# --- 1. Nœuds et versions -----------------------------------------------------------------------
title "1/9 Nœuds et versions"
check_cmd "exactement six nœuds : k8s-cp01-03 et k8s-w01-03 (k8s-w04 retiré)" _m14p_jq "$_m14_e46_noeuds" \
  '[.items[].metadata.name] | sort == ["k8s-cp01","k8s-cp02","k8s-cp03","k8s-w01","k8s-w02","k8s-w03"]'
check_cmd "tous Ready, aucun cordonné, aucune pression" _m14p_jq "$_m14_e46_noeuds" \
  'all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True")
     and (.spec.unschedulable // false) == false
     and ([.status.conditions[] | select((.type | test("Pressure$")) and .status == "True")] | length == 0))'
check_cmd "kubelet en 1.36.x partout" _m14p_jq "$_m14_e46_noeuds" \
  'all(.items[]; .status.nodeInfo.kubeletVersion | test("^v1\\.36\\."))'
check_cmd "runtime containerd 2.3.x partout" _m14p_jq "$_m14_e46_noeuds" \
  'all(.items[]; .status.nodeInfo.containerRuntimeVersion | test("^containerd://2\\.3\\."))'
for _m14_e46_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e46_n : kube-apiserver en v1.36.x, prêt" bash -c \
    'jq -e ".spec.containers[0].image | test(\":v1\\\\.36\\\\.\")" >/dev/null <<<"$1" && jq -e ".status.phase == \"Running\"" >/dev/null <<<"$1"' \
    _ "$(_m14p_pod_statique kube-apiserver "$_m14_e46_n")"
done
_m14_e46_vm_absente() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
    jq -e '[.[] | select(.vmid == 2147)] | length == 0' >/dev/null 2>&1
}
check_cmd "VM 2147 (k8s-w04) détruite" _m14_e46_vm_absente
_m14_e46_nb_w04() {
  netbox_api "virtualization/virtual-machines/?name=k8s-w04" 2>/dev/null | jq -e '.count == 0 or (.results[0].status.value != "active")' >/dev/null
}
check_cmd "NetBox : k8s-w04 absent ou non actif" _m14_e46_nb_w04
_m14_e46_dns_w04() {
  local r
  r="$(dig +time=3 +tries=1 @10.10.20.10 k8s-w04.par1.medisphere.internal A 2>/dev/null)" || return 1
  grep -q 'status: NXDOMAIN' <<<"$r" || { grep -q 'status: NOERROR' <<<"$r" && ! grep -q 'ANSWER SECTION' <<<"$r"; }
}
check_cmd "DNS : k8s-w04 n'est plus publié (dns01 répond sans adresse)" _m14_e46_dns_w04

# --- 2. Point d'accès de l'API et haute disponibilité ----------------------------------------------
title "2/9 Point d'accès de l'API"
_m14_e46_direct() {
  [[ "$(kube --server "https://$1:6443" --tls-server-name k8s-api.par1.medisphere.internal get --raw /livez 2>/dev/null)" == ok ]] &&
    [[ "$(kube --server "https://$1:6443" --tls-server-name 10.10.40.200 get --raw /livez 2>/dev/null)" == ok ]]
}
for _m14_e46_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e46_n : kube-apiserver en direct, certificat valable pour la VIP (nom et adresse)" \
    _m14_e46_direct "${_M14P_IP[$_m14_e46_n]}"
  check_cmd "$_m14_e46_n : HAProxy et keepalived actifs, keepalived suit son contrôle" _m14x_noeud "$_m14_e46_n" \
    'systemctl is-active -q haproxy && systemctl is-active -q keepalived && f=/etc/keepalived/keepalived.conf && { ! grep -q "^[[:space:]]*vrrp_script" "$f" || grep -q "^[[:space:]]*track_script" "$f"; }'
done
_m14_e46_porteurs() {
  local h n=0
  for h in "${_M14P_CP[@]}"; do
    remote "$h" "ip -4 -o addr show | grep -qw 10.10.40.200" </dev/null >/dev/null 2>&1 && n=$((n + 1))
  done
  ((n == 1))
}
check_cmd "VIP 10.10.40.200 portée par exactement un nœud de contrôle" _m14_e46_porteurs

# --- 3. etcd et sauvegarde -------------------------------------------------------------------------
title "3/9 etcd et sauvegarde"
check_output "etcd : trois membres en bonne santé" '^3$' \
  _m14x_etcd 'e_ --endpoints="$EP" endpoint health 2>&1 | grep -c "is healthy"'
check_output "etcd : aucune alarme" '^vide$' _m14x_etcd 'a="$(e_ alarm list 2>/dev/null)"; [ -z "$a" ] && echo vide'
for _m14_e46_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e46_n : minuterie etcd-instantane.timer active" _m14x_noeud "$_m14_e46_n" 'systemctl is-active -q etcd-instantane.timer'
  check_output "$_m14_e46_n : dernier instantané etcd réussi il y a moins de 2 h" '^ok$' \
    bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 < 7200 )) && echo ok' _ "$(_m14p_age_succes "$_m14_e46_n")"
done
_m14_e46_s3_recent() {
  local l d
  l="$(_m14p_s3 s3api list-objects-v2 --bucket "$_M14P_COMPARTIMENT" --prefix horaire/ 2>/dev/null)" || return 1
  d="$(jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .LastModified // empty' <<<"$l")"
  [[ -n "$d" ]] && (($(date +%s) - $(date -d "$d" +%s) < 7200))
}
check_cmd "s3-01 : un instantané de moins de 2 h dans etcd-k8s-par1/horaire/" _m14_e46_s3_recent
check_cmd "PBS : sauvegarde de k8s-cp01 (2141) de moins de 48 h dans par1/k8s" _m14p_pbs_vm_recente 2141 48
check_cmd "test de restauration d'etcd consigné (docs/kubernetes/tests/restauration-etcd*)" \
  _m14p_doc_prefixe docs/kubernetes/tests restauration-etcd 'RTO|dur[ée]e'

# --- 4. Certificats ---------------------------------------------------------------------------------
title "4/9 Certificats"
for _m14_e46_n in "${_M14P_CP[@]}"; do
  check_output "$_m14_e46_n : aucun certificat kubeadm n'expire dans moins de 30 jours" '^ok$' \
    _m14x_noeud_sortie "$_m14_e46_n" 'kubeadm certs check-expiration -o json 2>/dev/null | python3 -c "
import json, sys, datetime
d = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
fins = [c[\"expirationDate\"] for c in d.get(\"certificates\", []) + d.get(\"certificateAuthorities\", [])]
ok = fins and all((datetime.datetime.fromisoformat(f.replace(\"Z\", \"+00:00\")) - now).days >= 30 for f in fins)
print(\"ok\" if ok else \"ko\")"'
done

# --- 5. Sécurité ------------------------------------------------------------------------------------
title "5/9 Sécurité"
for _m14_e46_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e46_n : audit (--audit-policy-file) et chiffrement des Secrets (--encryption-provider-config)" bash -c \
    'jq -e "[.spec.containers[0].command[] | select(test(\"^--(audit-policy-file|encryption-provider-config)=\"))] | length == 2" >/dev/null <<<"$1"' \
    _ "$(_m14p_pod_statique kube-apiserver "$_m14_e46_n")"
done
for _m14_e46_ns in mediagenda-dev mediagenda-recette; do
  check_cmd "$_m14_e46_ns : Pod Security « restricted » imposé, quota et LimitRange présents" bash -c \
    'jq -e ".metadata.labels[\"pod-security.kubernetes.io/enforce\"] == \"restricted\"" >/dev/null <<<"$1" && [ "$2" -ge 1 ] && [ "$3" -ge 1 ]' _ \
    "$(_m14p_json get namespace "$_m14_e46_ns")" \
    "$(_m14p_json -n "$_m14_e46_ns" get resourcequota | jq '.items | length' 2>/dev/null || echo 0)" \
    "$(_m14p_json -n "$_m14_e46_ns" get limitrange | jq '.items | length' 2>/dev/null || echo 0)"
done
check_cmd "au moins une ValidatingAdmissionPolicy liée en Deny" _m14x_kq \
  '[.items[] | select(.spec.validationActions | index("Deny"))] | length >= 1' validatingadmissionpolicybindings
check_cmd "cluster-admin réservé à kubeadm:cluster-admins, system:masters et medisphere:plateforme-admins (pour les groupes et utilisateurs)" \
  _m14x_kq '[.items[] | select(.roleRef.name == "cluster-admin") | .subjects[]? | select(.kind != "ServiceAccount") | .name]
            | all(. == "kubeadm:cluster-admins" or . == "system:masters" or . == "medisphere:plateforme-admins")' clusterrolebindings
_m14_e46_checks_secrets() { kube auth can-i get secrets -A 2>/dev/null || true; }
check_output "le compte des checks ne lit pas les Secrets (auth can-i)" '^no$' _m14_e46_checks_secrets

# --- 6. Composants de plateforme --------------------------------------------------------------------
title "6/9 Composants de plateforme"
check_cmd "Cilium : DaemonSet prêt sur les six nœuds" _m14x_kq \
  '.status.desiredNumberScheduled == 6 and .status.numberReady == 6' -n kube-system daemonset cilium
check_cmd "Hubble relay disponible" _m14x_deploy_pret kube-system hubble-relay
check_cmd "CoreDNS : au moins 2 réplicas disponibles" _m14x_kq \
  '(.spec.replicas // 0) >= 2 and (.status.availableReplicas // 0) == .spec.replicas' -n kube-system deploy coredns
check_cmd "kube-proxy (mode iptables, conservé au M14) prêt sur les six nœuds" _m14x_kq \
  '.status.numberReady == 6' -n kube-system daemonset kube-proxy
check_cmd "metrics-server : APIService v1beta1.metrics.k8s.io disponible" _m14x_kq \
  'any(.status.conditions[]?; .type == "Available" and .status == "True")' apiservice v1beta1.metrics.k8s.io
check_cmd "aucun pod de kube-system en CrashLoopBackOff ou en échec de tirage" \
  _m14x_pods_sans '(.state.waiting.reason // "") | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull")' kube-system

# --- 7. MédiAgenda en recette -----------------------------------------------------------------------
title "7/9 MédiAgenda dans mediagenda-recette"
_m14_e46_app="$(_m14p_json -n mediagenda-recette get deploy)"
check_cmd "un déploiement MédiAgenda (image Harbor medisphere/mediagenda-api, étiquette v* ou digest) disponible avec au moins 2 réplicas" \
  _m14p_jq "$_m14_e46_app" '[.items[] | select(any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-api(:v[0-9]|@sha256:)")))
     | select((.spec.replicas // 1) >= 2 and (.status.availableReplicas // 0) == .spec.replicas)] | length >= 1'
check_cmd "aucune image « latest » ni hors de Harbor dans mediagenda-recette" _m14x_kq \
  '[.items[].spec.containers[].image | select(test(":latest$") or (startswith("registry.par1.medisphere.internal/") | not))] | length == 0' \
  -n mediagenda-recette pods
check_cmd "un PodDisruptionBudget protège MédiAgenda en recette" _m14x_kq '.items | length >= 1' -n mediagenda-recette pdb
check_cmd "le Service de l'API a des points d'accès prêts" _m14x_kq \
  '[.items[] | select(.metadata.labels["kubernetes.io/service-name"] != null) | .endpoints[]? | select(.conditions.ready == true)] | length >= 2' \
  -n mediagenda-recette endpointslices
check_cmd "aucun conteneur en boucle ni en échec de tirage dans mediagenda-*" \
  _m14x_pods_sans '(.state.waiting.reason // "") | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull")' mediagenda-dev mediagenda-recette

# --- 8. Rien de provisoire ------------------------------------------------------------------------
title "8/9 Rien de provisoire"
check_cmd "aucune panne M14 encore marquée active (lab/bin/break)" _m14x_aucune_panne_active
_m14_e46_pending() {
  local ns
  for ns in $(_m14x_espaces_workbook) kube-system; do
    kube -n "$ns" get pods -o json 2>/dev/null | jq -e '[.items[] | select(.status.phase == "Pending")
      | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 300)] | length == 0' >/dev/null 2>&1 || return 1
  done
}
check_cmd "aucun pod Pending depuis plus de 5 min (workbook et kube-system)" _m14_e46_pending
check_cmd "aucune taint « maintenance » sur les nœuds" _m14p_jq "$_m14_e46_noeuds" '[.items[].spec.taints[]? | select(.key == "maintenance")] | length == 0'

# --- 9. Documentation et livraison -----------------------------------------------------------------
title "9/9 Documentation et livraison"
check_cmd "docs/kubernetes/architecture.md (main) : composants, ce qui n'est pas redondant" \
  _m14p_doc_prefixe docs/kubernetes architecture 'etcd' 'VIP|keepalived' 'redondant'
for _m14_e46_adr in ADR-0140 ADR-0141; do
  check_cmd "$_m14_e46_adr publié (main)" _m14p_doc_prefixe docs/kubernetes/adr "$_m14_e46_adr" '.'
done
for _m14_e46_rb in RB-140 RB-141 RB-142 RB-143 RB-144 RB-145 RB-146 RB-147 RB-148 RB-149; do
  check_cmd "runbook $_m14_e46_rb publié (main)" _m14p_doc_prefixe docs/kubernetes/runbooks "$_m14_e46_rb" '.'
done
check_cmd "matrice des flux : VLAN 40 → reg01 443 et s3-01 8333 décrits" \
  _m14p_fichier_contient plateforme/medisphere docs/socle/matrice-flux.md '10\.10\.40\.0/24|VLAN 40|K8S' '8333' 'reg01|10\.10\.20\.18'
for _m14_e46_f in cluster/kubeadm-config.yaml Taskfile.yml; do
  check_cmd "plateforme/k8s : $_m14_e46_f sur main" _m14p_fichier_contient plateforme/k8s "$_m14_e46_f" '.'
done
_m14_e46_pipeline() { gitlab_api "projects/plateforme%2Fk8s/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1; }
check_cmd "plateforme/k8s : dernier pipeline de main réussi" _m14_e46_pipeline
_m14_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/k8s-v1' 2>/dev/null | jq -e '.name == "k8s-v1"' >/dev/null 2>&1; }
check_cmd "étiquette k8s-v1 posée sur plateforme/medisphere" _m14_e46_etiquette
