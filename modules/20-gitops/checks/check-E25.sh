# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E25.sh — M20-E25 « Durcir Argo CD » (SEC-2125)
# À lancer depuis adm01. Lecture seule (wb-checks) : NetworkPolicy et CiliumNetworkPolicy de l'espace
# argocd, ConfigMaps argocd-cm et argocd-cmd-params-cm, images des pods, état des Applications ;
# GitLab (documentation sur main).

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E25 — Durcir Argo CD"
require_cmd kubectl jq curl
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

title "Politiques réseau de l'espace argocd"
_m20_e25_np="$(_m20p_json -n argocd get networkpolicies)"
_m20_e25_cnp="$(_m20p_json -n argocd get ciliumnetworkpolicies)"
check_cmd "refus par défaut en entrée ET en sortie pour tout l'espace (NetworkPolicy, podSelector vide)" _m20p_jq "$_m20_e25_np" \
  'any(.items[]; (.spec.podSelector | length) == 0 and ((.spec.podSelector.matchLabels // {}) | length) == 0
       and ((.spec.policyTypes // []) | index("Ingress") and index("Egress"))
       and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)'
check_cmd "plus aucune NetworkPolicy du chart (argocd-*) dans l'espace" _m20p_jq "$_m20_e25_np" \
  '[.items[] | select(.metadata.name | startswith("argocd-"))] | length == 0'
for _m20_e25_c in argocd-server argocd-repo-server argocd-application-controller argocd-applicationset-controller \
  argocd-notifications-controller argocd-redis argocd-redis-secret-init; do
  check_cmd "une CiliumNetworkPolicy sélectionne $_m20_e25_c" _m20p_jq "$_m20_e25_cnp" \
    "any(.items[]; .spec.endpointSelector.matchLabels[\"app.kubernetes.io/name\"] == \"$_m20_e25_c\")"
done
# Politique(s) du repo-server : sorties hors cluster par NOM seulement (git01, registry/reg01) en 443 ;
# aucune entité large (world, all, cluster, remote-node, host) ; aucun CIDR plus large qu'une adresse.
_m20_e25_repo='[.items[] | select(.spec.endpointSelector.matchLabels["app.kubernetes.io/name"] == "argocd-repo-server") | .spec.egress[]?]'
check_cmd "repo-server : aucune sortie vers une entité large ni un réseau entier" _m20p_jq "$_m20_e25_cnp" \
  "$_m20_e25_repo"' | all(.[]; ((.toEntities // []) | all(. == "kube-apiserver"))
       and ((.toCIDR // []) | all(endswith("/32")))
       and ((.toCIDRSet // []) | all(.cidr | endswith("/32"))))'
check_cmd "repo-server : sorties par nom limitées à git01 et registry/reg01, en 443" _m20p_jq "$_m20_e25_cnp" \
  "$_m20_e25_repo"' | [.[] | select(.toFQDNs)] as $f
     | ($f | length) > 0
       and all($f[]; all(.toFQDNs[]; (.matchName // .matchPattern // "") | test("^(git01|registry|reg01)\\.par1\\.medisphere\\.internal$"))
                     and all(.toPorts[]?.ports[]?; .port == "443"))
       and any($f[].toFQDNs[]; .matchName == "git01.par1.medisphere.internal")'
check_cmd "argocd-server : entrée par la Gateway (entité ingress) seulement" _m20p_jq "$_m20_e25_cnp" \
  '[.items[] | select(.spec.endpointSelector.matchLabels["app.kubernetes.io/name"] == "argocd-server") | .spec.ingress[]?] as $i
   | ($i | length) > 0 and all($i[]; (.fromEntities // []) == ["ingress"] and (.fromEndpoints == null) and (.fromCIDR == null))'

title "Réglages d'argocd-cm et argocd-cmd-params-cm"
_m20_e25_cm="$(_m20p_cm argocd-cm)"
_m20_e25_params="$(_m20p_cm argocd-cmd-params-cm)"
check_cmd "exec.enabled écrit à « false »" _m20p_jq "$_m20_e25_cm" '.data["exec.enabled"] == "false"'
check_cmd "users.anonymous.enabled écrit à « false »" _m20p_jq "$_m20_e25_cm" '.data["users.anonymous.enabled"] == "false"'
_m20_e25_session="$(jq -r '.data["users.session.duration"] // ""' <<<"$_m20_e25_cm" 2>/dev/null || true)"
_m20_e25_session_s="$(_m20p_duree_s "$_m20_e25_session" || true)"
check_output "durée de session explicite de 12 h au plus (users.session.duration = ${_m20_e25_session:-absent})" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 && $1 <= 43200 )) && echo ok' _ "$_m20_e25_session_s"
check_cmd "application.sync.requireOverridePrivilegeForRevisionSync à « true »" _m20p_jq "$_m20_e25_cm" \
  '.data["application.sync.requireOverridePrivilegeForRevisionSync"] == "true"'
check_cmd "aucun compte local humain n'a la capacité apiKey" _m20p_jq "$_m20_e25_cm" \
  '[.data // {} | to_entries[] | select(.key | test("^accounts\\.[^.]+$")) | select(.key != "accounts.ci-lecture")
    | select(.value | test("apiKey"))] | length == 0'
check_cmd "ci-lecture : capacité apiKey, sans login" _m20p_jq "$_m20_e25_cm" \
  '(.data["accounts.ci-lecture"] // "") as $c | ($c | test("apiKey")) and ($c | test("login") | not)'
check_cmd "applications et ApplicationSets limités à l'espace argocd (pas de *.namespaces)" _m20p_jq "$_m20_e25_params" \
  '((.data["application.namespaces"] // "") == "") and ((.data["applicationsetcontroller.namespaces"] // "") == "")'
check_cmd "exclusions de ressources : objets de Velero exclus" _m20p_jq "$_m20_e25_cm" \
  '(.data["resource.exclusions"] // "") | test("velero\\.io")'

title "Images épinglées"
# Pods des composants (ReplicaSet, StatefulSet) ; les pods de Job (sauvegarde, crochets) sont exclus.
_m20_e25_pods="$(_m20p_json -n argocd get pods)"
check_cmd "il y a des pods d'Argo CD en cours d'exécution" _m20p_jq "$_m20_e25_pods" \
  'any(.items[]; .status.phase == "Running")'
check_cmd "tous les conteneurs d'Argo CD et de Redis : image registry.par1… référencée par empreinte (@sha256:)" _m20p_jq "$_m20_e25_pods" \
  '[.items[] | select(any(.metadata.ownerReferences[]?; .kind == "ReplicaSet" or .kind == "StatefulSet"))
    | (.spec.initContainers // []) + .spec.containers | .[] | .image]
   | length > 0 and all(.[]; startswith("registry.par1.medisphere.internal/") and test("@sha256:[0-9a-f]{64}$"))'

title "Argo CD fonctionne toujours"
_m20_e25_apps="$(_m20p_json -n argocd get applications.argoproj.io)"
check_cmd "aucune Application en état de synchronisation Unknown (dépôt ou API injoignables)" _m20p_jq "$_m20_e25_apps" \
  '(.items | length) > 0 and all(.items[]; .status.sync.status != "Unknown")'
check_cmd "aucune erreur de comparaison (ComparisonError)" _m20p_jq "$_m20_e25_apps" \
  'all(.items[]; all(.status.conditions[]?; .type != "ComparisonError"))'
check_cmd "l'Application racine est Synced/Healthy" _m20p_app_saine "$(_m20p_app racine)"

title "Documentation"
check_cmd "docs/livraison/gitops/durcissement-argocd.md sur main (mesures et ce qui reste ouvert)" \
  _m20p_doc docs/livraison/gitops/durcissement-argocd.md 'exec' 'session' 'ouvert'
check_cmd "matrice des flux du cluster : section Argo CD (repo-server → git01)" \
  _m20p_doc docs/kubernetes/reseau/matrice-flux-cluster.md 'argocd-repo-server' 'git01'
