# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M26-E17 : politiques d'admission natives (VAP et MAP)
# À lancer depuis adm01. Lecture seule : objets admissionregistration.k8s.io, ConfigMap de paramètres
# et pods (compte wb-checks), fichiers des dépôts (API GitLab).
# Ce qui est vérifié : les trois politiques et leurs liaisons (mode, périmètre, paramètres) ; que
# chaque montage hostPath EN SERVICE est autorisé par la ConfigMap (sinon l'agent sera refusé à son
# prochain redémarrage) ; que la MAP n'utilise pas namespaceObject dans ses matchConditions (elle ne
# ferait rien) ; les fichiers sur main.

# shellcheck source=_m26-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel-c.sh"

title "M26-E17 — Politiques d'admission natives : ValidatingAdmissionPolicy et MutatingAdmissionPolicy"
require_cmd jq kubectl curl

# --- hostPath -------------------------------------------------------------------------------------
_m26c_e17_vap="$(_m26c_k get validatingadmissionpolicy medisphere-interdire-hostpath -o json)"
_m26c_e17_lia="$(_m26c_k get validatingadmissionpolicybinding medisphere-interdire-hostpath -o json)"
check_cmd "VAP medisphere-interdire-hostpath : paramétrée par une ConfigMap, vise les pods et leurs contrôleurs" \
  _m26c_json "$_m26c_e17_vap" '.spec.paramKind.kind == "ConfigMap"
    and any(.spec.matchConstraints.resourceRules[]; .resources | index("pods"))
    and any(.spec.matchConstraints.resourceRules[]; .resources | index("daemonsets"))'
check_cmd "liaison medisphere-interdire-hostpath : en Deny, paramètre kube-system/medisphere-hostpath" \
  _m26c_json "$_m26c_e17_lia" '.spec.validationActions == ["Deny"]
    and .spec.paramRef.name == "medisphere-hostpath" and .spec.paramRef.namespace == "kube-system"'
check_cmd "liaison medisphere-interdire-hostpath : kube-system est exclu (couche de base)" \
  _m26c_json "$_m26c_e17_lia" 'any(.spec.matchResources.namespaceSelector.matchExpressions[]?;
    .key == "kubernetes.io/metadata.name" and .operator == "NotIn" and (.values | index("kube-system")))'

_m26c_e17_cm="$(_m26c_k get configmap -n kube-system medisphere-hostpath -o json)"
check_cmd "ConfigMap kube-system/medisphere-hostpath : une clé par espace d'agents (falco, supervision-noeuds, journaux)" \
  _m26c_json "$_m26c_e17_cm" '.data | has("falco") and has("supervision-noeuds") and has("journaux")'

# Chaque hostPath en service est autorisé pour son espace (même règle que la VAP : chemin exact ou sous-dossier).
_m26c_e17_conformes() {
  local pods
  pods="$(kube get pods -A -o json 2>/dev/null)" || return 1
  [[ -n "$_m26c_e17_cm" ]] || return 1
  jq -e --argjson cm "$_m26c_e17_cm" '
    [ .items[] | select(.metadata.namespace as $n | ["kube-system", "cilium"] | index($n) | not)
      | .metadata.namespace as $ns | .metadata.name as $pod
      | (($cm.data[$ns] // "") | split(",") | map(gsub("^ +| +$"; "")) | map(select(. != ""))) as $ok
      | .spec.volumes[]? | select(.hostPath) | .hostPath.path as $c
      | select(any($ok[]; $c == . or ($c | startswith(if endswith("/") then . else . + "/" end))) | not)
      | "\($ns)/\($pod) \($c)" ] | length == 0' <<<"$pods" >/dev/null
}
check_cmd "chaque montage hostPath en service (hors kube-system) est autorisé par la ConfigMap pour son espace" \
  _m26c_e17_conformes

# --- Étiquettes d'espace ---------------------------------------------------------------------------
check_cmd "VAP medisphere-etiquettes-espace-protegees : mises à jour de Namespace, compare oldObject et userInfo" \
  _m26c_json "$(_m26c_k get validatingadmissionpolicy medisphere-etiquettes-espace-protegees -o json)" '
    any(.spec.matchConstraints.resourceRules[]; (.resources | index("namespaces")) and (.operations | index("UPDATE")))
    and ([.. | strings] | any(test("oldObject"))) and ([.. | strings] | any(test("userInfo")))'
check_cmd "liaison medisphere-etiquettes-espace-protegees : en Deny" \
  _m26c_json "$(_m26c_k get validatingadmissionpolicybinding medisphere-etiquettes-espace-protegees -o json)" \
  '.spec.validationActions | index("Deny")'

# --- Mutation -------------------------------------------------------------------------------------
_m26c_e17_map="$(_m26c_k get mutatingadmissionpolicy medisphere-etiquette-equipe-par-defaut -o json)"
check_cmd "MAP medisphere-etiquette-equipe-par-defaut : création de pods, mutation ApplyConfiguration" \
  _m26c_json "$_m26c_e17_map" '
    any(.spec.matchConstraints.resourceRules[]; (.resources | index("pods")) and (.operations | index("CREATE")))
    and any(.spec.mutations[]; .patchType == "ApplyConfiguration")'
check_cmd "MAP : ses matchConditions n'utilisent pas namespaceObject (indisponible à cet endroit : la MAP ne ferait rien)" \
  _m26c_json "$_m26c_e17_map" '[.spec.matchConditions[]?.expression] | all(test("namespaceObject") | not)'
check_cmd "liaison de la MAP limitée aux espaces d'équipe (medisphere.internal/equipe)" \
  _m26c_json "$(_m26c_k get mutatingadmissionpolicybinding medisphere-etiquette-equipe-par-defaut -o json)" '
    any(.spec.matchResources.namespaceSelector.matchExpressions[]?; .key == "medisphere.internal/equipe" and .operator == "Exists")
    or (.spec.matchResources.namespaceSelector.matchLabels // {} | has("medisphere.internal/equipe"))'

# --- Dépôts ---------------------------------------------------------------------------------------
for _m26c_e17_f in admission/20-interdire-hostpath.yaml admission/30-etiquette-equipe-par-defaut.yaml \
  admission/40-etiquettes-espace-protegees.yaml; do
  check_cmd "plateforme/k8s : $_m26c_e17_f sur main" _m26c_fichier "$_M26C_P_K8S" "$_m26c_e17_f"
done
check_cmd "plateforme/medisphere : $_M26C_DOC/admission-native-ou-kyverno.md sur main" \
  _m26c_fichier "$_M26C_P_DOC" "$_M26C_DOC/admission-native-ou-kyverno.md"
