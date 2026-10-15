# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E33.sh — M14-E33 « Accueillir une équipe sur le cluster » (MédiDoc, DEV-1533)
# À lancer depuis adm01. Lecture seule : espace, quota, LimitRange, liaisons d'admission, liaisons RBAC
# et rôles (API, compte wb-checks), compte de service et pods de medidoc-dev, dépôts GitLab.
# L'évaluation des droits porte sur les RÔLES liés au groupe (lecture des objets RBAC), pas sur des
# essais d'écriture : un check ne crée rien.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E33 — Accueillir l'équipe MédiDoc"
require_cmd kubectl jq
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_M14_E33_NS=medidoc-dev
_M14_E33_GROUPE=medisphere:medidoc-devs
_m14_e33_ns="$(_m14p_json get namespace "$_M14_E33_NS")"

title "Espace et enveloppe"
check_cmd "l'espace $_M14_E33_NS existe" _m14p_jq "$_m14_e33_ns" '.metadata.name == "medidoc-dev"'
check_cmd "Pod Security restricted en enforce" _m14p_jq "$_m14_e33_ns" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
# Quantités : l'API conserve l'écriture d'origine ; on accepte les formes équivalentes courantes.
check_cmd "ResourceQuota conforme à l'enveloppe (2/4 CPU, 4/8 Gio, 20 pods, 0 LoadBalancer, 0 NodePort)" bash -c '
  jq -e "any(.items[]; .spec.hard as \$h
    | ((\$h[\"requests.cpu\"] // \"\") | IN(\"2\", \"2000m\"))
    and ((\$h[\"limits.cpu\"] // \"\") | IN(\"4\", \"4000m\"))
    and ((\$h[\"requests.memory\"] // \"\") | IN(\"4Gi\", \"4096Mi\"))
    and ((\$h[\"limits.memory\"] // \"\") | IN(\"8Gi\", \"8192Mi\"))
    and (\$h.pods // \"\") == \"20\"
    and (\$h[\"services.loadbalancers\"] // \"\") == \"0\"
    and (\$h[\"services.nodeports\"] // \"\") == \"0\")" >/dev/null <<<"$1"' _ "$(_m14p_json -n "$_M14_E33_NS" get resourcequota)"
check_cmd "LimitRange avec des demandes par défaut pour les conteneurs" bash -c \
  'jq -e "any(.items[].spec.limits[]; .type == \"Container\" and (.defaultRequest | type) == \"object\" and (.default | type) == \"object\")" >/dev/null <<<"$1"' \
  _ "$(_m14p_json -n "$_M14_E33_NS" get limitrange)"

title "Admission"
# Une liaison s'applique si elle n'a pas de namespaceSelector, ou si ses matchLabels et matchExpressions
# (In, NotIn, Exists, DoesNotExist) sont satisfaits par les étiquettes de l'espace.
_m14_e33_vapb="$(_m14p_json get validatingadmissionpolicybindings)"
_m14_e33_etiquettes="$(jq -c '.metadata.labels // {}' <<<"$_m14_e33_ns" 2>/dev/null || echo '{}')"
check_cmd "au moins une ValidatingAdmissionPolicyBinding existante s'applique à $_M14_E33_NS" bash -c '
  jq -e --argjson l "$2" "any(.items[]; (.spec.matchResources.namespaceSelector // null) as \$s
    | if \$s == null or \$s == {} then true
      else (all((\$s.matchLabels // {}) | to_entries[]; \$l[.key] == .value)
        and all((\$s.matchExpressions // [])[];
          if .operator == \"In\" then (\$l[.key] as \$v | \$v != null and (.values | index(\$v)) != null)
          elif .operator == \"NotIn\" then (\$l[.key] as \$v | \$v == null or (.values | index(\$v)) == null)
          elif .operator == \"Exists\" then \$l | has(.key)
          else (\$l | has(.key) | not) end))
      end)" >/dev/null <<<"$1"' _ "$_m14_e33_vapb" "$_m14_e33_etiquettes"

title "Droits du groupe $_M14_E33_GROUPE"
_m14_e33_rb="$(_m14p_json get rolebindings -A)"
_m14_e33_crb="$(_m14p_json get clusterrolebindings)"
_m14_e33_roles="$(_m14p_json -n "$_M14_E33_NS" get roles)"
_m14_e33_croles="$(_m14p_json get clusterroles)"
_M14_E33_SUJET='any(.subjects[]?; .kind == "Group" and .name == "medisphere:medidoc-devs")'
check_cmd "un RoleBinding dans $_M14_E33_NS lie le groupe" _m14p_jq "$_m14_e33_rb" \
  "any(.items[]; .metadata.namespace == \"$_M14_E33_NS\" and $_M14_E33_SUJET)"
check_cmd "aucun RoleBinding du groupe hors de $_M14_E33_NS" _m14p_jq "$_m14_e33_rb" \
  "[.items[] | select($_M14_E33_SUJET) | select(.metadata.namespace != \"$_M14_E33_NS\")] | length == 0"
# Règles des rôles liés au groupe dans l'espace (Role ou ClusterRole référencé).
_m14_e33_regles="$(jq -c --argjson roles "$_m14_e33_roles" --argjson croles "$_m14_e33_croles" "
  [.items[] | select(.metadata.namespace == \"$_M14_E33_NS\" and $_M14_E33_SUJET) | .roleRef as \$r
   | (if \$r.kind == \"Role\" then \$roles.items[] else \$croles.items[] end) | select(.metadata.name == \$r.name)
   | .rules[]?]" <<<"$_m14_e33_rb" 2>/dev/null || echo null)"
check_cmd "le rôle de l'équipe permet de créer des Deployments" _m14p_jq "$_m14_e33_regles" \
  'any(.[]; ((.apiGroups // []) | index("apps") or index("*")) and ((.resources // []) | index("deployments") or index("*"))
       and ((.verbs // []) | index("create") or index("*")))'
check_cmd "le rôle de l'équipe ne permet ni de modifier les quotas ni de toucher au RBAC ou à l'espace" _m14p_jq "$_m14_e33_regles" \
  '[.[] | select((.verbs // []) | any(IN("create", "update", "patch", "delete", "deletecollection", "escalate", "bind", "*")))
        | select((.resources // []) | any(IN("resourcequotas", "limitranges", "roles", "rolebindings", "namespaces", "*")))]
   | length == 0'
_m14_e33_cregles="$(jq -c --argjson croles "$_m14_e33_croles" "
  [.items[] | select($_M14_E33_SUJET) | .roleRef.name as \$n | \$croles.items[] | select(.metadata.name == \$n) | .rules[]?]" \
  <<<"$_m14_e33_crb" 2>/dev/null || echo null)"
check_cmd "hors de l'espace, le groupe n'a que des droits de lecture" _m14p_jq "$_m14_e33_cregles" \
  'all(.[]; (.verbs // []) | all(IN("get", "list", "watch")))'

title "Images et pods"
check_cmd "le compte default de $_M14_E33_NS tire les images avec harbor-pull" bash -c \
  'jq -e "any(.imagePullSecrets[]?; .name == \"harbor-pull\")" >/dev/null <<<"$1"' \
  _ "$(_m14p_json -n "$_M14_E33_NS" get serviceaccount default)"
check_cmd "un pod MédiDoc (image du projet Harbor medisphere) tourne dans $_M14_E33_NS" bash -c \
  'jq -e "any(.items[]; .status.phase == \"Running\" and any(.spec.containers[]; .image | startswith(\"registry.par1.medisphere.internal/medisphere/medidoc:\")))" >/dev/null <<<"$1"' \
  _ "$(_m14p_json -n "$_M14_E33_NS" get pods)"

title "Code et documentation"
_m14_e33_decrit() { [[ -n "$(_m14p_arbre plateforme/k8s "espaces/$_M14_E33_NS" 2>/dev/null)" ]]; }
check_cmd "plateforme/k8s : description de $_M14_E33_NS sur main" _m14_e33_decrit
check_cmd "procédure d'accueil sur main" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/accueil-equipe.md 'can-i' 'enveloppe|quota'
check_cmd "fiche de l'équipe MédiDoc sur main" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/equipes/medidoc.md 'medidoc-dev' 'medidoc-devs'
