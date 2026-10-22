# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E03.sh — M20-E03 : Accéder à Argo CD : interface, CLI et comptes locaux
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API d'Argo CD en GET avec le jeton
# ci-lecture, existence d'un Secret par le kubeconfig personnel (jamais son contenu), API GitLab.

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E03 — Accéder à Argo CD : interface, CLI et comptes locaux"
require_cmd jq kubectl curl

# --- 1. La CLI sur adm01 ---------------------------------------------------------------------------
check_output "CLI argocd 3.5.x installée sur adm01" 'argocd: v3\.5\.[0-9]+' argocd version --client --short
check_output "plateforme/ansible (main) : la CLI argocd est décrite dans le rôle outils_k8s" 'argocd-linux-amd64' \
  _m20d_contenu_main plateforme/ansible roles/outils_k8s/defaults/main.yml

# --- 2. Le jeton des vérifications ----------------------------------------------------------------
if [[ ! -r "$_M20D_JETON" ]]; then
  skip "Jeton ci-lecture et contrôles par l'API d'Argo CD" "fichier $_M20D_JETON absent : étape 6 de l'énoncé"
else
  check_output "Fichier du jeton en 600 (lisible par toi seul)" '^600$' stat -c '%a' "$_M20D_JETON"
  _m20d_e03_qui="$(_m20d_argocd_api session/userinfo || true)"
  check_cmd "Le jeton ouvre une session sur l'API : compte ci-lecture" _m20d_json "$_m20d_e03_qui" \
    '.loggedIn == true and .username == "ci-lecture"'
  check_cmd "ci-lecture ne peut pas synchroniser (rôle en lecture seule)" _m20d_json \
    "$(_m20d_argocd_api 'account/can-i/applications/sync/*' || true)" '.value == "no"'

  # --- 3. Les comptes locaux -----------------------------------------------------------------------
  _m20d_e03_comptes="$(_m20d_argocd_api account || true)"
  # Un compte désactivé est rendu SANS champ « enabled » (valeur par défaut omise).
  check_cmd "Compte admin désactivé" _m20d_json "$_m20d_e03_comptes" \
    '[.items[] | select(.name == "admin")] | length == 1 and ((.[0].enabled // false) == false)'
  for _m20d_e03_c in karim-benali julien-petit nadia-roussel; do
    check_cmd "Compte local $_m20d_e03_c : actif, connexion interactive (login)" _m20d_json "$_m20d_e03_comptes" \
      '[.items[] | select(.name == $c and (.enabled // false) and ((.capabilities // []) | index("login")))] | length == 1' \
      --arg c "$_m20d_e03_c"
  done
  if [[ -n "$_M20D_MOI_ARGO" ]]; then
    check_cmd "Ton compte local ${_M20D_MOI_ARGO} : actif, connexion interactive" _m20d_json "$_m20d_e03_comptes" \
      '[.items[] | select(.name == $c and (.enabled // false) and ((.capabilities // []) | index("login")))] | length == 1' \
      --arg c "$_M20D_MOI_ARGO"
  else
    skip "Ton compte local dans Argo CD" "WB_MOI non renseigné dans lab/lab.env"
  fi
  check_cmd "Aucun compte au nom tronqué (un point dans un nom de compte le coupe en deux)" _m20d_json "$_m20d_e03_comptes" \
    '[.items[] | select((.capabilities // []) | length == 0)] | length == 0'
  _m20d_e03_ci="$(_m20d_argocd_api account/ci-lecture || true)"
  check_cmd "ci-lecture : jetons d'API seulement (pas de connexion interactive)" _m20d_json "$_m20d_e03_ci" \
    '(.capabilities // []) == ["apiKey"]'
  check_cmd "ci-lecture : tous ses jetons ont une date d'expiration" _m20d_json "$_m20d_e03_ci" \
    '(.tokens // []) | length >= 1 and all((.expiresAt // 0) > 0)'
fi

# --- 4. Configuration déclarative -----------------------------------------------------------------
_m20d_e03_cm="$(_m20d_k -n "$_M20D_NS" get configmap argocd-cm -o json)"
check_cmd "argocd-cm : admin.enabled = false" _m20d_json "$_m20d_e03_cm" '.data["admin.enabled"] == "false"'
check_cmd "argocd-cm : ci-lecture déclaré avec la seule capacité apiKey" _m20d_json "$_m20d_e03_cm" \
  '.data["accounts.ci-lecture"] | gsub(" "; "") == "apiKey"'
_m20d_e03_rbac="$(_m20d_k -n "$_M20D_NS" get configmap argocd-rbac-cm -o json)"
check_cmd "argocd-rbac-cm : rôle par défaut vide (un compte sans rôle ne voit rien)" _m20d_json "$_m20d_e03_rbac" \
  '(.data["policy.default"] // "") == ""'
check_cmd "argocd-rbac-cm : ci-lecture lié à role:readonly" _m20d_json "$_m20d_e03_rbac" \
  '.data["policy.csv"] // "" | test("(?m)^\\s*g\\s*,\\s*ci-lecture\\s*,\\s*role:readonly\\s*$")'
check_output "values d'Argo CD (main de plateforme/k8s) : admin.enabled à false" 'admin\.enabled:[[:space:]]*"?false' \
  _m20d_contenu_main plateforme/k8s composants/argocd/values.yaml

# --- 5. Le mot de passe initial a disparu ---------------------------------------------------------
case "$(_m20d_secret_existe "$_M20D_NS" argocd-initial-admin-secret)" in
  non) _ok "Secret argocd-initial-admin-secret supprimé" ;;
  oui) _ko "Secret argocd-initial-admin-secret encore présent (mot de passe initial lisible par qui lit les Secrets)" ;;
  *) skip "Secret argocd-initial-admin-secret supprimé" "API injoignable avec $_M20D_ADMIN_KCFG (identité personnelle expirée ?)" ;;
esac

# --- 6. Le compte des vérifications lit Argo CD ---------------------------------------------------
check_cmd "wb-checks peut lister les Applications d'Argo CD (wb-checks-livraison étendue)" _m20d_peut_lire_argo
check_output "wb-checks peut lister les AppProjects" '^yes$' \
  _m20d_k auth can-i list appprojects.argoproj.io -n "$_M20D_NS"
check_output "wb-checks ne lit toujours pas les Secrets d'argocd" '^no$' \
  _m20d_k auth can-i get secrets -n "$_M20D_NS"
