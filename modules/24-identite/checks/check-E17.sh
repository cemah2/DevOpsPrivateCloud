# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M24-E17 : RBAC Kubernetes par groupes de l'annuaire.
# Vérifie, en lecture seule depuis adm01 :
#   - les décisions de l'autorisateur pour des identités OIDC représentatives (SubjectAccessReview
#     avec le compte wb-checks : rien n'est écrit, aucune usurpation d'identité) ;
#   - l'absence de liaison nominative et de liaison aux groupes de certificats medisphere:* ;
#   - rbac/oidc.yaml et outils/matrice-droits-oidc.sh sur main de plateforme/k8s ;
#   - ton ~/.kube/config : contexte courant k8s-par1-oidc, k8s-par1 sur le même utilisateur, plus de
#     certificat client (lu localement, aucune valeur affichée) ;
#   - docs/kubernetes/acces.md mis à jour.

# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

title "M24-E17 — RBAC Kubernetes par groupes de l'annuaire"
require_cmd jq kubectl curl

if [[ -z "$(_m24c_k get --raw /readyz)" ]]; then
  _ko "API de k8s-par1 injoignable avec le compte des vérifications (lab/bin/check 14 06)"
  return 0
fi

# --- 1. Les droits, groupe par groupe -------------------------------------------------------------
check_cmd "oidc:plateforme-admins : administrateur du cluster (supprimer un pod de kube-system)" \
  _m24c_droit yes oidc:karim.benali oidc:plateforme-admins delete pods kube-system
check_cmd "oidc:plateforme : lit les pods de kube-system et les Applications d'Argo CD" \
  bash -c '[[ "$1" == yes && "$2" == yes ]]' _ \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme list pods kube-system)" \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme list applications argocd "" argoproj.io)"
check_cmd "oidc:plateforme : ne lit AUCUN Secret hors de wb-essais (kube-system, argocd)" \
  bash -c '[[ "$1" == no && "$2" == no ]]' _ \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme get secrets kube-system)" \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme list secrets argocd)"
check_cmd "oidc:plateforme : écrit dans wb-essais, pas dans kube-system" \
  bash -c '[[ "$1" == yes && "$2" == no ]]' _ \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme create deployments wb-essais "" apps)" \
  "$(_m24c_peut oidc:lucas.martin oidc:plateforme delete pods kube-system)"
check_cmd "oidc:mediagenda : entre dans un pod de mediagenda-dev, pas de mediagenda-prod" \
  bash -c '[[ "$1" == yes && "$2" == no ]]' _ \
  "$(_m24c_peut oidc:julien.petit oidc:mediagenda create pods mediagenda-dev exec)" \
  "$(_m24c_peut oidc:julien.petit oidc:mediagenda create pods mediagenda-prod exec)"
check_cmd "oidc:mediagenda : lit les pods de mediagenda-prod mais pas ses Secrets, rien dans medidoc-dev" \
  bash -c '[[ "$1" == yes && "$2" == no && "$3" == no ]]' _ \
  "$(_m24c_peut oidc:julien.petit oidc:mediagenda list pods mediagenda-prod)" \
  "$(_m24c_peut oidc:julien.petit oidc:mediagenda get secrets mediagenda-prod)" \
  "$(_m24c_peut oidc:julien.petit oidc:mediagenda list pods medidoc-dev)"
check_cmd "oidc:medidoc : lit medidoc-recette, n'écrit pas dans medidoc-dev" \
  bash -c '[[ "$1" == yes && "$2" == no ]]' _ \
  "$(_m24c_peut oidc:essai.medidoc oidc:medidoc list pods medidoc-recette)" \
  "$(_m24c_peut oidc:essai.medidoc oidc:medidoc patch deployments medidoc-dev "" apps)"
check_cmd "oidc:support : lit les nœuds, ne supprime rien, ne lit aucun Secret" \
  bash -c '[[ "$1" == yes && "$2" == no && "$3" == no ]]' _ \
  "$(_m24c_peut oidc:nadia.roussel oidc:support list nodes)" \
  "$(_m24c_peut oidc:nadia.roussel oidc:support delete pods mediagenda-prod)" \
  "$(_m24c_peut oidc:nadia.roussel oidc:support get secrets mediagenda-prod)"
check_cmd "oidc:securite : lit les pods et le RBAC (qui a quel droit), ne modifie rien, ne lit aucun Secret" \
  bash -c '[[ "$1" == yes && "$2" == no && "$3" == no && "$4" == yes ]]' _ \
  "$(_m24c_peut oidc:sophie.laurent oidc:securite list clusterrolebindings "" "" rbac.authorization.k8s.io)" \
  "$(_m24c_peut oidc:sophie.laurent oidc:securite create clusterrolebindings "" "" rbac.authorization.k8s.io)" \
  "$(_m24c_peut oidc:sophie.laurent oidc:securite get secrets kube-system)" \
  "$(_m24c_peut oidc:sophie.laurent oidc:securite list pods kube-system)"
check_cmd "oidc:direction et un groupe « system:masters » venu de l'annuaire : aucun droit" \
  bash -c '[[ "$1" == no && "$2" == no ]]' _ \
  "$(_m24c_peut oidc:claire.morel oidc:direction list pods mediagenda-prod)" \
  "$(_m24c_peut oidc:intrus oidc:system:masters list secrets kube-system)"

# --- 2. Les liaisons -----------------------------------------------------------------------------
_m24c_e17_liaisons="$(_m24c_k get clusterrolebindings,rolebindings -A -o json)"
check_cmd "Aucune liaison ne vise une personne nommée (sujet User oidc:…)" _m24c_json "$_m24c_e17_liaisons" \
  '[.items[].subjects[]? | select(.kind == "User" and (.name | startswith("oidc:")))] | length == 0'
check_cmd "Plus aucune liaison aux groupes de certificats personnels (medisphere:*)" _m24c_json "$_m24c_e17_liaisons" \
  '(.items | length > 0) and ([.items[].subjects[]? | select(.kind == "Group" and (.name | startswith("medisphere:")))] | length == 0)'
check_cmd "Toutes les liaisons des groupes oidc:* s'appellent oidc-*" _m24c_json "$_m24c_e17_liaisons" \
  '[.items[] | select([.subjects[]? | select(.kind == "Group" and (.name | startswith("oidc:")))] | length > 0)] as $l
   | ($l | length) >= 5 and ($l | all(.metadata.name | startswith("oidc-")))'

# --- 3. Le dépôt ---------------------------------------------------------------------------------
check_cmd "rbac/oidc.yaml sur main de plateforme/k8s (groupes préfixés oidc:)" \
  _m24c_sur_main plateforme/k8s rbac/oidc.yaml 'name: "?oidc:plateforme-admins'
check_cmd "outils/matrice-droits-oidc.sh sur main de plateforme/k8s" \
  _m24c_sur_main plateforme/k8s outils/matrice-droits-oidc.sh 'can-i'

# --- 4. Ton poste ----------------------------------------------------------------------------------
_m24c_e17_kubeconfig="$(kubectl config view -o json 2>/dev/null || true)"
check_cmd "Ton kubeconfig : contexte courant k8s-par1-oidc" _m24c_json "$_m24c_e17_kubeconfig" \
  '.["current-context"] == "k8s-par1-oidc"'
check_cmd "Ton kubeconfig : le contexte k8s-par1 utilise le même utilisateur que k8s-par1-oidc (kubelogin)" \
  _m24c_json "$_m24c_e17_kubeconfig" \
  '([.contexts[] | select(.name == "k8s-par1-oidc") | .context.user][0]) as $u
   | $u != null and ([.contexts[] | select(.name == "k8s-par1") | .context.user][0] == $u)
   and ([.users[] | select(.name == $u) | .user.exec.args // [] | map(tostring) | any(test("oidc-login|get-token"))] | any)'
check_cmd "Ton kubeconfig : plus aucun utilisateur à certificat client" _m24c_json "$_m24c_e17_kubeconfig" \
  '[.users[] | select(.user["client-certificate-data"] != null or .user["client-certificate"] != null)] | length == 0'

# --- 5. La documentation ------------------------------------------------------------------------------
check_cmd "docs/kubernetes/acces.md sur main de plateforme/medisphere décrit les identités OIDC et le bris de glace" \
  bash -c 'grep -q "oidc:" <<<"$1" && grep -Eqi "admin\.conf" <<<"$1" && grep -Eqi "kubelogin|oidc-login" <<<"$1"' _ \
  "$(_m24c_contenu_main plateforme/medisphere docs/kubernetes/acces.md)"
