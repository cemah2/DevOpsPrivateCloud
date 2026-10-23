# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq entre apostrophes
#
# check-E22.sh — M26-E22 : revue des manifestes et du Dockerfile du stagiaire
# À lancer depuis adm01. Lecture seule de tes fichiers de travail : ~/m26/e22/revue.md et
# ~/m26/e22/corrige/ (Dockerfile, values.yaml, manifestes). Rien n'est lu dans le cluster.
# Ce qui est vérifié : le nombre de défauts relevés, et l'ABSENCE dans ta version corrigée des défauts
# bloquants et majeurs (privilèges, accès à l'hôte, secrets en clair, rôle à « * », réseau ouvert,
# image flottante, root, ressources, exposition, espace default).

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E22 — Revue : les manifestes et le Dockerfile du stagiaire"
require_cmd yq jq

_m26c_e22="$_M26C_TRAVAIL/e22"
_m26c_e22_revue="$_m26c_e22/revue.md"
_m26c_e22_dir="$_m26c_e22/corrige"

# Défauts relevés : lignes de tableau numérotées (« | 3 | … ») ou éléments numérotés (« 3. » / « 3) »).
_m26c_e22_nb_defauts() {
  [[ -r "$_m26c_e22_revue" ]] || { echo 0; return; }
  grep -cE '^[[:space:]]*(\|[[:space:]]*[0-9]+[[:space:]]*\||[0-9]+[.)][[:space:]])' "$_m26c_e22_revue" || true
}
_m26c_e22_douze() { (( $(_m26c_e22_nb_defauts) >= 12 )); }
check_cmd "revue.md (dossier de travail m26/e22) relève au moins douze défauts (lignes numérotées)" _m26c_e22_douze

# Tous les documents YAML de la version corrigée, en un flux JSON (yq de mikefarah).
_m26c_e22_yaml() {
  find "$_m26c_e22_dir" -type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'values.yaml' -print0 2>/dev/null \
    | xargs -0 -r yq -o=json -I=0 '.' 2>/dev/null | jq -s '[.[] | select(type == "object")]' 2>/dev/null || true
}
_m26c_e22_objets="$(_m26c_e22_yaml)"
_m26c_e22_a() { _m26c_json "$_m26c_e22_objets" "$1"; }

# Spécifications de pod de tous les objets de charge.
_M26C_E22_PODS='[.[] | if .kind == "Pod" then .spec elif .kind == "CronJob" then .spec.jobTemplate.spec.template.spec
  elif (.kind | test("^(Deployment|StatefulSet|DaemonSet|ReplicaSet|Job)$")) then .spec.template.spec else empty end]'

check_cmd "version corrigée : au moins un Deployment lisible dans le dossier de travail m26/e22/corrige" \
  _m26c_e22_a 'any(.[]; .kind == "Deployment")'
check_cmd "version corrigée : ni privileged, ni hostNetwork/hostPID/hostIPC, ni hostPath" \
  _m26c_e22_a "$_M26C_E22_PODS"' | length >= 1 and all(
    ((.hostNetwork // false) | not) and ((.hostPID // false) | not) and ((.hostIPC // false) | not)
    and ([.volumes[]? | select(has("hostPath"))] | length == 0)
    and ([.containers[], (.initContainers // [])[] | .securityContext.privileged // false] | all(. == false)))'
check_cmd "version corrigée : processus non root, capacités retirées (ALL), aucun ajout, pas d'escalade" \
  _m26c_e22_a "$_M26C_E22_PODS"' | length >= 1 and all(. as $p | [.containers[], (.initContainers // [])[]] | all(
    ((.securityContext.runAsNonRoot // $p.securityContext.runAsNonRoot) == true)
    and ((.securityContext.capabilities.drop // []) | index("ALL"))
    and ((.securityContext.capabilities.add // []) | length == 0)
    and .securityContext.allowPrivilegeEscalation == false))'
check_cmd "version corrigée : images du registre MédiSphère, ni « latest » ni sans version" \
  _m26c_e22_a "$_M26C_E22_PODS"' | length >= 1 and all([.containers[], (.initContainers // [])[] | .image] | all(
    startswith("registry.par1.medisphere.internal/") and (test(":latest($|@)") | not) and test("[:@]")))'
check_cmd "version corrigée : demandes et limite de mémoire sur chaque conteneur" \
  _m26c_e22_a "$_M26C_E22_PODS"' | length >= 1 and all([.containers[], (.initContainers // [])[]] | all(
    .resources.requests.cpu and .resources.requests.memory and .resources.limits.memory))'
check_cmd "version corrigée : aucun secret en clair dans les variables (TOKEN, PASSWORD, SECRET, KEY : valueFrom)" \
  _m26c_e22_a "$_M26C_E22_PODS"' | all([.containers[], (.initContainers // [])[] | .env[]?
    | select(.name | test("TOKEN|PASSWORD|PASSWD|SECRET|KEY"; "i"))] | all(has("valueFrom") and (has("value") | not)))'
check_cmd "version corrigée : aucun rôle RBAC avec « * » (groupes, ressources ou verbes)" \
  _m26c_e22_a '[.[] | select(.kind == "Role" or .kind == "ClusterRole") | .rules[]? | [.apiGroups[]?, .resources[]?, .verbs[]?]]
    | flatten | all(. != "*")'
check_cmd "version corrigée : aucune politique réseau « tout autoriser » (règle vide)" \
  _m26c_e22_a '[.[] | select(.kind == "NetworkPolicy" or .kind == "CiliumNetworkPolicy")] as $np
    | ($np | length) >= 1 and ($np | all([.spec.ingress[]?, .spec.egress[]?] | all(. != {})))'
check_cmd "version corrigée : Service interne (ni LoadBalancer ni NodePort), espace autre que default" \
  _m26c_e22_a '([.[] | select(.kind == "Service") | .spec.type // "ClusterIP"] | all(. == "ClusterIP"))
    and ([.[] | .metadata.namespace // ""] | all(. != "default"))'

# Dockerfile corrigé : utilisateur numérique non nul, base du registre MédiSphère, aucun secret de build,
# aucun outil de débogage installé.
_m26c_e22_df="$_m26c_e22_dir/Dockerfile"
_m26c_e22_dockerfile_ok() {
  [[ -r "$_m26c_e22_df" ]] || return 1
  grep -qE '^[[:space:]]*USER[[:space:]]+[1-9][0-9]*(:[0-9]+)?[[:space:]]*$' "$_m26c_e22_df" || return 1
  ! grep -qiE '^[[:space:]]*(ARG|ENV)[[:space:]].*(TOKEN|PASSWORD|SECRET)' "$_m26c_e22_df" || return 1
  ! grep -qiE '^[[:space:]]*FROM[[:space:]]+[^[:space:]]*:latest' "$_m26c_e22_df" || return 1
  ! grep -qiE 'apt-get install[^#]*(vim|netcat|tcpdump|[[:space:]]gcc)' "$_m26c_e22_df" || return 1
  # Chaque FROM désigne le registre MédiSphère, directement ou par un ARG.
  ! grep -E '^[[:space:]]*FROM[[:space:]]' "$_m26c_e22_df" | grep -vqE 'registry\.par1\.medisphere\.internal/|\$\{?[A-Z_]+\}?'
}
check_cmd "Dockerfile corrigé : USER numérique non root, base MédiSphère, sans secret ni outils de débogage" \
  _m26c_e22_dockerfile_ok
