# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E19.sh — M25-E19 « Comparer : Sealed Secrets et Secrets Store CSI ».
# Vérifie l'état FINAL de l'exercice : la comparaison est écrite et décidée ; les essais ont bien eu
# lieu (historique de plateforme/gitops, SealedSecret produit dans ~/m25/e19/) ET tout est retiré :
# Applications, espaces, CRD, politique OpenBao d'essai, Secret en clair.
# Lecture seule. Une absence se prouve par « NotFound » (un refus d'accès n'est pas une absence).

# shellcheck source=_m25-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel-c.sh"

title "M25-E19 — Comparer : Sealed Secrets et Secrets Store CSI"
require_cmd jq yq kubectl curl

_m25c_e19_doc="$_M25C_DOC_SECRETS/comparatif-livraison-k8s.md"
check_cmd "comparaison : section Sealed Secrets (et Secrets Store CSI, contrôlé ci-dessous)" \
  _m25c_contient "$_M25C_P_DOC" "$_m25c_e19_doc" '[Ss]ealed [Ss]ecrets'
check_cmd "comparaison : la décision nomme chaque approche (ESO, CSI, Sealed Secrets, SOPS)" \
  bash -c 'c="$1"; for m in "External Secrets|ESO" "CSI" "Sealed Secrets" "SOPS" "[Dd]écision"; do grep -Eq "$m" <<<"$c" || exit 1; done' _ \
  "$(_m25c_contenu "$_M25C_P_DOC" "$_m25c_e19_doc")"

# Les essais ont eu lieu : ajout PUIS retrait des Applications dans plateforme/gitops.
_m25c_e19_histoire() {
  local f="plateforme/$1.yaml"
  [[ "$(_m25c_commits_chemin "$_M25C_P_GITOPS" "$f")" -ge 2 ]] && ! _m25c_fichier "$_M25C_P_GITOPS" "$f"
}
for _m25c_e19_app in essai-sealed-secrets essai-csi-driver essai-openbao-csi; do
  check_cmd "plateforme/gitops : Application $_m25c_e19_app ajoutée puis retirée par MR" _m25c_e19_histoire "$_m25c_e19_app"
  check_cmd "Application $_m25c_e19_app absente d'Argo CD" _m25c_absent applications.argoproj.io "$_m25c_e19_app" -n argocd
done

for _m25c_e19_ns in sealed-secrets essai-csi; do
  check_cmd "espace $_m25c_e19_ns supprimé" _m25c_absent namespace "$_m25c_e19_ns"
done
check_cmd "CRD SealedSecret supprimée (sealedsecrets.bitnami.com)" _m25c_absent crd sealedsecrets.bitnami.com
check_cmd "CRD SecretProviderClass supprimée (secretproviderclasses.secrets-store.csi.x-k8s.io)" \
  _m25c_absent crd secretproviderclasses.secrets-store.csi.x-k8s.io

_m25c_e19_pols="$(_m25c_politiques)"
if [[ -z "$_m25c_e19_pols" ]]; then
  check_cmd "liste des politiques OpenBao lisible par wb-checks" false
else
  check_cmd "politique d'essai essai-csi retirée d'OpenBao" bash -c '! grep -qx essai-csi <<<"$1"' _ "$_m25c_e19_pols"
fi

_m25c_e19_scelle="$(_m25c_travail e19/sealedsecret.yaml)"
if [[ ! -r "$_m25c_e19_scelle" ]]; then
  check_cmd "SealedSecret d'essai conservé ($_m25c_e19_scelle)" false
else
  check_cmd "SealedSecret d'essai : wb-essais, portée stricte, valeurs scellées" \
    bash -c 'yq -o=json "." "$1" | jq -e '\''.kind == "SealedSecret" and .metadata.namespace == "wb-essais"
      and ((.spec.encryptedData // {}) | length > 0)
      and ((.metadata.annotations // {}) | has("sealedsecrets.bitnami.com/cluster-wide") or has("sealedsecrets.bitnami.com/namespace-wide") | not)'\'' >/dev/null' _ "$_m25c_e19_scelle"
fi
check_cmd "Secret en clair de l'essai détruit (~/m25/e19/secret-a-sceller.yaml absent)" \
  test ! -e "$(_m25c_travail e19/secret-a-sceller.yaml)"
