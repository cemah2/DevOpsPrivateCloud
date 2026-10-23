# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M28-E05 : Capsule : un locataire par équipe
# Lecture seule : Applications, contrôleur, CapsuleConfiguration, Tenant, GlobalTenantResource, Namespaces,
# ResourceQuotas, LimitRanges
# (kube) ; questions d'autorisation (SubjectAccessReview : rien n'est modifié) ; document (GitLab, GET).
# Rejouable après les paliers 3 et 4 (seuls les invariants du modèle sont contrôlés).

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E05 — Capsule : un locataire par équipe"
require_cmd jq kubectl curl

# --- 1. Capsule ------------------------------------------------------------------------------------------
check_cmd "Application Argo CD capsule : Synced et Healthy" _m28d_app_saine capsule
check_cmd "capsule-system/capsule-controller-manager prêt, image de Harbor en 0.15" _m28d_deploy_pret \
  capsule-system capsule-controller-manager '^registry\.par1\.medisphere\.internal/.+/projectcapsule/capsule:v?0\.15\.[0-9]+'
check_cmd "webhooks de Capsule enregistrés (validation)" _m28d_kq \
  '[.items[].metadata.name | select(test("capsule"))] | length >= 1' validatingwebhookconfigurations.admissionregistration.k8s.io
check_cmd "CapsuleConfiguration : utilisateurs = groupes oidc:mediagenda et oidc:medidoc ; préfixe imposé" _m28d_kq \
  '([.spec.users[]? | select(.kind == "Group") | .name] | (index("oidc:mediagenda") != null and index("oidc:medidoc") != null))
   and .spec.forceTenantPrefix == true' capsuleconfigurations.capsule.clastix.io default
check_cmd "Application Argo CD locataires : Synced" _m28d_app_synced locataires

# --- 2. Les trois locataires ------------------------------------------------------------------------------------
for _m28d_e05_t in mediagenda:oidc:mediagenda medidoc:oidc:medidoc medinotif:oidc:mediagenda; do
  _m28d_e05_n="${_m28d_e05_t%%:*}"
  _m28d_e05_g="${_m28d_e05_t#*:}"
  check_cmd "Tenant $_m28d_e05_n : actif, propriétaires = groupe $_m28d_e05_g seulement (aucune personne)" _m28d_kq \
    '(.status.state // "") == "Active" and (.spec.owners | length >= 1) and all(.spec.owners[]; .kind == "Group")
     and ([.spec.owners[].name] | index($g) != null)' \
    tenants.capsule.clastix.io "$_m28d_e05_n" -- --arg g "$_m28d_e05_g"
  check_cmd "Tenant $_m28d_e05_n : propriétaires sans admin ni cluster-admin sur tous les espaces" _m28d_kq \
    'all(.spec.owners[]; (.clusterRoles // ["admin"]) | (index("admin") == null and index("cluster-admin") == null))' \
    tenants.capsule.clastix.io "$_m28d_e05_n"
  check_cmd "Tenant $_m28d_e05_n : protégé contre la suppression (preventDeletion et Delete=false d'Argo CD)" _m28d_kq \
    '.spec.preventDeletion == true and ((.metadata.annotations["argocd.argoproj.io/sync-options"] // "") | test("Delete=false"))' \
    tenants.capsule.clastix.io "$_m28d_e05_n"
  check_cmd "Tenant $_m28d_e05_n : classe ceph-rbd seule ; nombre d'espaces et budget (règle quota) définis" _m28d_kq \
    '.spec.storageClasses.allowed == ["ceph-rbd"] and (.spec.namespaceOptions.quota // 0) >= 1
     and ([.spec.rules[]? | select((.quota // []) | length >= 1)] | length >= 1)' \
    tenants.capsule.clastix.io "$_m28d_e05_n"
done

# --- 3. Rattachement des espaces existants ------------------------------------------------------------------------
for _m28d_e05_r in mediagenda-dev:mediagenda mediagenda-recette:mediagenda mediagenda-prod:mediagenda \
  mediagenda-secours:mediagenda medidoc-dev:medidoc medidoc-recette:medidoc medinotif-recette:medinotif medinotif-prod:medinotif; do
  _m28d_e05_ns="${_m28d_e05_r%%:*}"
  _m28d_e05_t="${_m28d_e05_r##*:}"
  check_cmd "$_m28d_e05_ns rattaché à $_m28d_e05_t (étiquette, référence de propriétaire) et marqué comme environnement" _m28d_kq \
    '.metadata.labels["capsule.clastix.io/tenant"] == $t and ((.metadata.labels["medisphere.internal/environnement"] // "") != "")
     and ([.metadata.ownerReferences[]? | select(.kind == "Tenant" and .name == $t)] | length == 1)' \
    namespace "$_m28d_e05_ns" -- --arg t "$_m28d_e05_t"
done
for _m28d_e05_ns in mediagenda-recette mediagenda-prod medidoc-dev medinotif-prod; do
  check_cmd "$_m28d_e05_ns : le quota de la plateforme est toujours là" _m28d_kq \
    '[.items[].metadata.name | select(startswith("capsule-") | not)] | length >= 1' -n "$_m28d_e05_ns" resourcequotas
done
check_cmd "Application mediagenda-prod toujours Synced" _m28d_app_synced mediagenda-prod
check_cmd "Application mediagenda-recette toujours Synced" _m28d_app_synced mediagenda-recette

# --- 4. LimitRange de la plateforme dans chaque espace des locataires ------------------------------------------------
# Chaque espace qui porte capsule.clastix.io/tenant (environnements ET libre-service) a au moins une LimitRange
# de type Container avec un minimum CPU et mémoire (une request déclarée nulle est refusée). Une LimitRange
# sans « min » (valeurs par défaut seules) ne suffit pas.
_m28d_e05_limites_partout() {
  local ns n
  ns="$(kube get namespaces -l capsule.clastix.io/tenant -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$ns" ]] || return 1
  for n in $ns; do
    kube -n "$n" get limitranges -o json 2>/dev/null | jq -e '
      any(.items[].spec.limits[]?; .type == "Container" and (.min.cpu // null) != null and (.min.memory // null) != null)' \
      >/dev/null 2>&1 || return 1
  done
}
check_cmd "GlobalTenantResource limites-par-defaut prête (Ready)" _m28d_kq \
  '[.status.conditions[]? | select(.type == "Ready")] | (length >= 1 and all(.[]; .status == "True"))' \
  globaltenantresources.capsule.clastix.io limites-par-defaut
check_cmd "chaque espace des locataires a une LimitRange avec un minimum CPU et mémoire par conteneur" \
  _m28d_e05_limites_partout

# --- 5. Droits de l'équipe -------------------------------------------------------------------------------------------
check_cmd "oidc:mediagenda ne peut toujours PAS créer un Deployment dans mediagenda-prod" _m28d_ne_peut_pas \
  oidc:wb-checks-sonde oidc:mediagenda create deployments mediagenda-prod apps
check_cmd "oidc:mediagenda ne peut PAS supprimer l'espace mediagenda-prod" _m28d_ne_peut_pas \
  oidc:wb-checks-sonde oidc:mediagenda delete namespaces mediagenda-prod
check_cmd "oidc:mediagenda lit toujours ses pods de production (view)" _m28d_peut \
  oidc:wb-checks-sonde oidc:mediagenda list pods mediagenda-prod

check_cmd "plateforme/medisphere : docs/plateforme-dev/locataires.md (droits, cohabitation, retour arrière)" \
  _m28d_doc docs/plateforme-dev/locataires.md 'libre-service' 'Pod Security|PSA' 'Kyverno' 'quota' 'retour arri'
