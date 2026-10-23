# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E02.sh — M29-E02 : kubeconform : valider les manifestes avec leurs CRD
# À lancer depuis adm01. Lecture seule : fichiers sur main (GitLab), paquet générique schemas-crd de
# plateforme/k8s (liste, puis téléchargement dans un dossier temporaire), CRD servies par le cluster
# (« kube »), kubeconform local rejoué sur un manifeste témoin contenant une faute de frappe.

# shellcheck source=_m29-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-decouverte.sh"

title "M29-E02 — kubeconform : valider les manifestes avec leurs CRD"
require_cmd jq curl kubectl tar

check_cmd "kubeconform 0.8 sur adm01" _m29d_version_outil kubeconform '^v0\.8\.'

# --- 1. L'outil de génération, dans plateforme/k8s ------------------------------------------------
check_cmd "plateforme/k8s : outils/schemas-crd.sh lit les CRD du cluster (kubectl get crd…)" \
  _m29d_contient "$_M29D_P_K8S" outils/schemas-crd.sh 'get (customresourcedefinitions|crds?)\b'
check_cmd "plateforme/k8s : conversion par le script officiel (outils/openapi2jsonschema.py)" \
  _m29d_contient "$_M29D_P_K8S" outils/openapi2jsonschema.py 'def additional_properties'
check_cmd "plateforme/k8s : schemas-crd.sh publie le paquet générique schemas-crd" \
  _m29d_contient "$_M29D_P_K8S" outils/schemas-crd.sh 'packages/generic/schemas-crd'

# --- 2. Le paquet publié -----------------------------------------------------------------------------
_m29d_e02_paquets="$(gitlab_api "projects/$(_m29d_uri "$_M29D_P_K8S")/packages?package_type=generic&package_name=schemas-crd&order_by=created_at&sort=desc&per_page=20" 2>/dev/null || true)"
check_cmd "paquet générique schemas-crd publié dans plateforme/k8s" _m29d_json "$_m29d_e02_paquets" \
  'map(select(.name == "schemas-crd")) | length >= 1'
_m29d_e02_version="$(jq -r '[.[] | select(.name == "schemas-crd")][0].version // empty' <<<"${_m29d_e02_paquets:-[]}" 2>/dev/null || true)"
check_cmd "version du paquet au format AAAA.MM.JJ[-N] (${_m29d_e02_version:-aucune})" \
  bash -c '[[ "$1" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[0-9]+)?$ ]]' _ "$_m29d_e02_version"

_m29d_e02_dossier="$_M29D_TMP/schemas"
mkdir -p "$_m29d_e02_dossier"
if [[ -n "$_m29d_e02_version" ]] \
  && gitlab_api "projects/$(_m29d_uri "$_M29D_P_K8S")/packages/generic/schemas-crd/$_m29d_e02_version/schemas-crd.tar.gz" >"$_M29D_TMP/schemas-crd.tar.gz" 2>/dev/null \
  && tar -xzf "$_M29D_TMP/schemas-crd.tar.gz" -C "$_m29d_e02_dossier" 2>/dev/null; then
  _ok "paquet schemas-crd $_m29d_e02_version téléchargé et lisible (archive tar.gz)"
  if gitlab_api "projects/$(_m29d_uri "$_M29D_P_K8S")/packages/generic/schemas-crd/$_m29d_e02_version/schemas-crd.tar.gz.sha256" >"$_M29D_TMP/schemas-crd.tar.gz.sha256" 2>/dev/null; then
    check_cmd "empreinte publiée avec le paquet (schemas-crd.tar.gz.sha256) conforme" \
      bash -c 'cd "$1" && sha256sum --check --quiet schemas-crd.tar.gz.sha256' _ "$_M29D_TMP"
  else
    _ko "empreinte schemas-crd.tar.gz.sha256 absente du paquet $_m29d_e02_version"
  fi
  check_cmd "paquet : api-versions.txt (API servies, pour helm template --api-versions)" \
    test -s "$_m29d_e02_dossier/api-versions.txt"
  check_cmd "paquet : schémas STRICTS (additionalProperties: false, script officiel — pas le schéma brut)" \
    bash -c 'grep -rlq "\"additionalProperties\": false" "$1" --include="*.json"' _ "$_m29d_e02_dossier"

  # Le paquet couvre-t-il les CRD servies AUJOURD'HUI par le cluster ?
  _m29d_e02_crd="$(_m29d_k get customresourcedefinitions -o json)"
  if [[ -n "$_m29d_e02_crd" ]]; then
    _m29d_e02_manquants="$(jq -r '.items[] | .spec.group as $g | (.spec.names.kind | ascii_downcase) as $k
        | .spec.versions[] | select(.served) | "\($g)/\($k)_\(.name).json"' <<<"$_m29d_e02_crd" 2>/dev/null \
      | while IFS= read -r f; do [[ -f "$_m29d_e02_dossier/$f" ]] || echo "$f"; done | head -5 | paste -sd' ' - || true)"
    check_cmd "paquet à jour : chaque CRD servie par k8s-par1 a son schéma (manquants : ${_m29d_e02_manquants:-aucun})" \
      bash -c '[[ -z "$1" ]]' _ "$_m29d_e02_manquants"
  else
    skip "couverture des CRD du cluster" "liste des CRD illisible par wb-checks"
  fi

  # Rejeu : une faute de frappe dans une ressource personnalisée doit être REFUSÉE avec ce paquet.
  _m29d_e02_crd_temoin="$(find "$_m29d_e02_dossier" -name 'application_v1alpha1.json' -path '*argoproj.io*' | head -1)"
  if [[ -n "$_m29d_e02_crd_temoin" ]] && command -v kubeconform >/dev/null 2>&1; then
    cat >"$_M29D_TMP/temoin.yaml" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: temoin
  namespace: argocd
spec:
  project: plateforme
  destination: {server: https://kubernetes.default.svc, namespace: wb-essais}
  source: {repoURL: https://git01.par1.medisphere.internal/plateforme/gitops.git, targetRevision: main, path: racine}
  syncPolicyy: {}
EOF
    check_output "kubeconform -strict + paquet : un champ inconnu dans une Application est refusé" \
      'additional properties .syncPolicyy. not allowed' \
      kubeconform -strict -schema-location default \
      -schema-location "$_m29d_e02_dossier/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" "$_M29D_TMP/temoin.yaml"
  else
    skip "rejeu kubeconform sur une Application fautive" "schéma argoproj.io/application_v1alpha1.json absent du paquet, ou kubeconform absent"
  fi
else
  _ko "paquet schemas-crd ${_m29d_e02_version:-?} : téléchargement ou décompression impossible"
fi

# --- 3. Les dépôts validés, et le piège --------------------------------------------------------------
check_cmd "plateforme/gitops : outils/rendre-charts.sh (rendu des charts des Applications)" \
  _m29d_existe "$_M29D_P_GITOPS" outils/rendre-charts.sh
for _m29d_e02_p in "$_M29D_P_K8S" "$_M29D_P_GITOPS" mediagenda/deploiement medinotif/deploiement; do
  _m29d_e02_ci="$(_m29d_contenu "$_m29d_e02_p" .gitlab-ci.yml)"
  check_cmd "$_m29d_e02_p : pas de -ignore-missing-schemas dans la CI" bash -c '[[ -n "$1" ]] && ! grep -q -- "-ignore-missing-schemas" <<<"$1"' _ "$_m29d_e02_ci"
done
check_cmd "plateforme/medisphere : docs/qualite/schemas-crd.md" _m29d_existe "$_M29D_P_DOC" docs/qualite/schemas-crd.md
