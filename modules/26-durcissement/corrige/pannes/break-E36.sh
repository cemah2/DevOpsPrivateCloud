# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq entre apostrophes
# break-E36.sh — M26-E36 « Panne : un pod privilégié est passé »
#
# Une charge qui aurait dû être refusée est admise. Les variantes 2 à 4 passent par un commit de
# lucas.martin ; la variante 1 est un objet posé à la main. Aucune ne touche kube-system, kyverno,
# argocd ni cilium :
#   1. une PolicyException posée à la main par Lucas dans kyverno-exceptions (le seul espace que Kyverno
#      lit, E18), hors de Git : elle exempte tout l'espace wb-pannes de « registres-autorises » ;
#   2. l'espace mediagenda-recette ré-étiqueté « pod-security.kubernetes.io/enforce: privileged »
#      (plateforme/k8s, espaces/) : un pod privilégié y est admis ;
#   3. le matchConstraints de « registres-autorises » exclut désormais wb-pannes (namespaceSelector NotIn) ;
#   4. la politique saute les requêtes du groupe system:masters (matchCondition) : l'admin n'est plus
#      filtré (« comme ça mes essais passent », Lucas).
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E36_NS_IMG=wb-pannes        # espace où « registres-autorises » doit refuser une image non autorisée
_E36_NS_PRIV=mediagenda-recette
_E36_NS_EXC=kyverno-exceptions  # espace des PolicyException (features.policyExceptions.namespace, E18)

# Pod dont l'image vient d'un registre non autorisé (refusé par registres-autorises, pas par PSA).
_e36_pod_image() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: wb-sonde-image, namespace: $_E36_NS_IMG, labels: {medisphere.internal/equipe: plateforme}}
spec:
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: docker.io/library/nginx:1.29
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 64Mi}}
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
EOF
}
# Pod privilégié (refusé par PSA restricted + politiques).
_e36_pod_priv() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: wb-sonde-priv, namespace: $_E36_NS_PRIV, labels: {medisphere.internal/equipe: mediagenda}}
spec:
  containers:
    - name: c
      image: registry.par1.medisphere.internal/dockerhub/library/busybox:1.37
      command: ["sleep", "1"]
      securityContext: {privileged: true}
EOF
}

_e36_fichier_registres() {
  m26_git_trouver "$_M26_PROJ_POL" '.kind == "ValidatingPolicy" and (.metadata.name | test("registre"))' kyverno/validation
}

# v1 : PolicyException trop large, posée à la main dans kyverno-exceptions (annulation = la retirer).
_e36_exception_yaml() {
  cat <<'EOF'
apiVersion: policies.kyverno.io/v1
kind: PolicyException
metadata:
  name: essai-lucas-wb-pannes
  namespace: kyverno-exceptions
spec:
  policyRefs:
    - name: registres-autorises
      kind: ValidatingPolicy
  matchConditions:
    - name: tout-wb-pannes
      expression: "object.metadata.namespace == 'wb-pannes'"
EOF
}
_e36_t3() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.matchConstraints.namespaceSelector.matchExpressions) += [{"key": "kubernetes.io/metadata.name", "operator": "NotIn", "values": ["wb-pannes"]}]'
}
_e36_i3() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.matchConstraints.namespaceSelector.matchExpressions) |= map(select(.values != ["wb-pannes"]))'
}
_e36_t4() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.matchConditions) += [{"name": "sauf-admins", "expression": "!(\"system:masters\" in request.userInfo.groups)"}]
      | (select(.kind == "ValidatingPolicy") | .spec.matchConditions[-1]) head_comment = "PLAT-2736 (Lucas) : ne pas me bloquer en urgence"'
}
_e36_i4() {
  yq '(select(.kind == "ValidatingPolicy") | .spec.matchConditions) |= map(select(.name != "sauf-admins"))'
}
# v2 : espace ré-étiqueté privileged.
_e36_t2() { yq '(select(.kind == "Namespace") | .metadata.labels."pod-security.kubernetes.io/enforce") = "privileged"'; }
_e36_i2() { yq '(select(.kind == "Namespace") | .metadata.labels."pod-security.kubernetes.io/enforce") = "restricted"'; }

_e36_effet() {
  case "$1" in
    2) _e36_pod_priv | wb_kubectl -n "$_E36_NS_PRIV" apply --dry-run=server -f - >/dev/null 2>&1 ;;
    *) _e36_pod_image | wb_kubectl -n "$_E36_NS_IMG" apply --dry-run=server -f - >/dev/null 2>&1 ;;
  esac
}

_m26E36_une() {
  local n="$1" f
  m26_ecrire E36 variante "$n"
  case "$n" in
    1)
      m26_sauver_objet E36 policyexception essai-lucas-wb-pannes "$_E36_NS_EXC"
      _e36_exception_yaml | wb_kubectl apply -f - >/dev/null || return 1
      ;;
    2)
      f="$(m26_git_trouver "$_M26_PROJ_K8S" '.kind == "Namespace" and .metadata.name == "mediagenda-recette"' espaces)" || return 10
      m26_git_transformer E36 ns "$_M26_PROJ_K8S" "$f" \
        "chore(espaces): recette en privileged le temps d'un essai (M26-E36)" _e36_t2 || return
      ;;
    3)
      f="$(_e36_fichier_registres)" || return 10
      m26_git_transformer E36 pol "$_M26_PROJ_POL" "$f" \
        "fix(validation): ne pas appliquer registres-autorises à wb-pannes (M26-E36)" _e36_t3 || return
      ;;
    4)
      f="$(_e36_fichier_registres)" || return 10
      m26_git_transformer E36 pol "$_M26_PROJ_POL" "$f" \
        "fix(validation): exempter les administrateurs (M26-E36)" _e36_t4 || return
      ;;
  esac
  m26_journal E36 "variante $n posée"
  m26_attendre 300 _e36_effet "$n" || { _e36_defaire "$n"; return 10; }
}

_e36_defaire() {
  case "$1" in
    1) m26_restaurer_objet E36 policyexception essai-lucas-wb-pannes "$_E36_NS_EXC" ;;
    2) m26_git_defaire E36 ns _e36_i2 "revert(espaces): recette en restricted (M26-E36, annulation)" ;;
    3) m26_git_defaire E36 pol _e36_i3 "revert(validation): registres-autorises couvre wb-pannes (M26-E36, annulation)" ;;
    4) m26_git_defaire E36 pol _e36_i4 "revert(validation): plus d'exemption des admins (M26-E36, annulation)" ;;
  esac
}

panne_E36_v1() { m26_kube_sain && m26_essayer E36 4 1; }
panne_E36_v2() { m26_kube_sain && m26_essayer E36 4 2; }
panne_E36_v3() { m26_kube_sain && m26_essayer E36 4 3; }
panne_E36_v4() { m26_kube_sain && m26_essayer E36 4 4; }

verifier_E36() { _e36_effet "$WB_VAR"; }

annuler_E36() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-4]$ ]] || v="$(m26_lire E36 variante)"
  [[ -n "$v" ]] && _e36_defaire "$v"
  m26_oublier E36 variante
  m26_journal E36 "annulation"
}

resume_E36() { echo "Une charge non conforme (image non autorisée ou pod privilégié) est admise alors qu'elle devrait être refusée."; }

symptome_E36() {
  wb_symptome "Ticket SEC-5336 — De : Sophie Laurent" \
    "Le rapport de politiques de ce matin (PolicyReport) montre une charge non conforme ADMISE" \
    "dans un espace applicatif : une image hors de notre registre, ou un pod privilégié." \
    "L'admission aurait dû la refuser. Je veux savoir par où c'est passé, et une preuve que le trou" \
    "est refermé (une charge d'essai refusée au bon endroit)." \
    "Lucas a touché aux politiques « pour débloquer un essai » cette semaine." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 26 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E36 4 "$@"; }
fi
