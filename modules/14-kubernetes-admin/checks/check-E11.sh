# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M14-E11 : RBAC : des rôles pour les équipes
# À lancer depuis adm01. Lecture seule : objets RBAC (« kube »), décisions d'autorisation par
# SubjectAccessReview (rien n'est écrit), API GitLab.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E11 — RBAC : des rôles pour les équipes"
require_cmd jq kubectl curl

_m14o_e11_cr="$(_m14o_k get clusterroles -o json)"
for _m14o_e11_r in medisphere-lecture medisphere-developpeur medisphere-lecture-charges medisphere-lecture-cluster \
                   medisphere-developpeur-ecriture medisphere-secrets-edition; do
  check_cmd "ClusterRole $_m14o_e11_r présent" _m14o_json "$_m14o_e11_cr" \
    'any(.items[]; .metadata.name == $n)' --arg n "$_m14o_e11_r"
done
check_cmd "medisphere-developpeur et medisphere-lecture sont agrégés et leurs règles ont été remplies" \
  _m14o_json "$_m14o_e11_cr" '[.items[] | select(.metadata.name == "medisphere-developpeur" or .metadata.name == "medisphere-lecture")
    | (.aggregationRule != null) and ((.rules // []) | length > 0)] | length == 2 and all'
check_cmd "aucun rôle MédiSphère n'accorde les Secrets, sauf medisphere-secrets-edition" \
  _m14o_json "$_m14o_e11_cr" '[.items[] | select((.metadata.name | startswith("medisphere-")) and .metadata.name != "medisphere-secrets-edition")
    | .rules[]? | select((.resources // []) | (index("secrets") != null or index("*") != null))] | length == 0'

_m14o_e11_rb="$(_m14o_k get rolebindings -A -o json)"
_m14o_e11_crb="$(_m14o_k get clusterrolebindings -o json)"
check_cmd "liaisons par GROUPE : medisphere:mediagenda-devs lié dans mediagenda-dev" \
  _m14o_json "$_m14o_e11_rb" 'any(.items[]; .metadata.namespace == "mediagenda-dev"
    and any(.subjects[]?; .kind == "Group" and .name == "medisphere:mediagenda-devs"))'
check_cmd "aucune liaison d'équipe faite à un utilisateur nominatif dans les espaces MédiAgenda" \
  _m14o_json "$_m14o_e11_rb" '[.items[] | select(.metadata.namespace | startswith("mediagenda-")) | .subjects[]? | select(.kind == "User")] | length == 0'
check_cmd "medisphere:lecture lié à l'échelle du cluster" \
  _m14o_json "$_m14o_e11_crb" 'any(.items[]; any(.subjects[]?; .kind == "Group" and .name == "medisphere:lecture"))'
check_cmd "cluster-admin n'est donné qu'à system:masters, kubeadm:cluster-admins, medisphere:plateforme-admins" \
  _m14o_json "$_m14o_e11_crb" '[.items[] | select(.roleRef.name == "cluster-admin") | .subjects[]?
    | select(.name != "system:masters" and .name != "kubeadm:cluster-admins" and .name != "medisphere:plateforme-admins")] | length == 0'
check_cmd "aucune liaison supplémentaire pour system:authenticated / system:unauthenticated" \
  _m14o_json "$_m14o_e11_crb" '[.items[] | select(any(.subjects[]?; .name == "system:authenticated" or .name == "system:unauthenticated"))
    | .metadata.name | select(. != "system:basic-user" and . != "system:discovery" and . != "system:public-info-viewer")] | length == 0'

# Matrice (SubjectAccessReview) : utilisateur, groupes, verbe, ressource, espace, sous-ressource, groupe d'API, attendu.
_m14o_e11_cas() {
  local desc="$1" attendu="$2"; shift 2
  check_output "$desc" "^$attendu\$" _m14o_peut "$@"
}
_D="medisphere:mediagenda-devs"; _L="medisphere:lecture"
_m14o_e11_cas "julien.petit peut créer des Deployments dans mediagenda-dev" yes julien.petit "$_D" create deployments mediagenda-dev "" apps
_m14o_e11_cas "julien.petit peut entrer dans un pod de mediagenda-dev (pods/exec)" yes julien.petit "$_D" create pods mediagenda-dev exec
_m14o_e11_cas "julien.petit gère les Secrets de mediagenda-dev" yes julien.petit "$_D" create secrets mediagenda-dev
_m14o_e11_cas "julien.petit ne modifie pas le quota de mediagenda-dev" no julien.petit "$_D" update resourcequotas mediagenda-dev
_m14o_e11_cas "julien.petit ne crée pas de RoleBinding" no julien.petit "$_D" create rolebindings mediagenda-dev "" rbac.authorization.k8s.io
_m14o_e11_cas "julien.petit lit les journaux en recette" yes julien.petit "$_D" get pods mediagenda-recette log
_m14o_e11_cas "julien.petit n'écrit rien en recette" no julien.petit "$_D" create deployments mediagenda-recette "" apps
_m14o_e11_cas "julien.petit n'entre pas dans les pods de recette" no julien.petit "$_D" create pods mediagenda-recette exec
_m14o_e11_cas "julien.petit ne lit pas les Secrets de recette" no julien.petit "$_D" get secrets mediagenda-recette
_m14o_e11_cas "julien.petit ne voit pas kube-system" no julien.petit "$_D" list pods kube-system
_m14o_e11_cas "le groupe lecture voit les nœuds" yes nadia.roussel "$_L" list nodes
_m14o_e11_cas "le groupe lecture voit kube-system" yes nadia.roussel "$_L" list pods kube-system
_m14o_e11_cas "le groupe lecture ne lit aucun Secret" no nadia.roussel "$_L" get secrets mediagenda-dev
_m14o_e11_cas "le groupe lecture ne supprime rien" no nadia.roussel "$_L" delete pods mediagenda-dev
_m14o_e11_cas "un authentifié quelconque ne liste pas les pods" no inconnu "system:authenticated" list pods mediagenda-dev

check_cmd "plateforme/k8s : au moins trois fichiers sous rbac/ sur main" \
  bash -c '[[ $(wc -l <<<"$1") -ge 3 ]]' _ "$(_m14o_arbre "$_M14O_P_K8S" rbac)"
check_cmd "matrice-droits.sh présent et exécutable dans ~/m14/e11/" test -x "$_M14O_TRAVAIL/e11/matrice-droits.sh"
