# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M19-E24 « Cloisonner les runners : comptes, Pod Security, réseau, quotas »
# À lancer depuis adm01. Lecture seule : espaces, comptes, RBAC (SubjectAccessReview), politiques
# réseau et ConfigMaps des runners (compte wb-checks) ; runners, pipelines, jobs et attributs des
# variables (sans valeurs) par l'API de GitLab ; documentation sur main.

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E24 — Cloisonner les runners"
require_cmd kubectl jq curl

title "Pod Security et comptes des pods de job"
for _m19_e24_ns in ci-jobs ci-jobs-protege; do
  check_output "$_m19_e24_ns : Pod Security « restricted » appliqué (enforce)" '^restricted$' \
    kube get namespace "$_m19_e24_ns" -o 'jsonpath={.metadata.labels.pod-security\.kubernetes\.io/enforce}'
  check_output "$_m19_e24_ns : le compte ci-job ne monte pas de jeton" '^false$' \
    kube -n "$_m19_e24_ns" get serviceaccount ci-job -o 'jsonpath={.automountServiceAccountToken}'
  check_output "$_m19_e24_ns : le compte ci-job ne peut pas lister les pods (aucun droit)" '^no$' \
    _m19p_peut "system:serviceaccount:$_m19_e24_ns:ci-job" list pods "$_m19_e24_ns"
done

title "Configuration des deux runners"
for _m19_e24_rel in gitlab-runner gitlab-runner-protege; do
  _m19_e24_toml="$(_m19p_toml "$_m19_e24_rel")"
  check_cmd "$_m19_e24_rel : configuration du runner lisible (ConfigMap du chart)" test -n "$_m19_e24_toml"
  check_cmd "$_m19_e24_rel : jeton du compte de service jamais monté dans les jobs" \
    _m19p_toml_a "$_m19_e24_toml" '^\s*automount_service_account_token\s*=\s*false'
  check_cmd "$_m19_e24_rel : toutes les capacités retirées (cap_drop = [\"ALL\"])" \
    _m19p_toml_a "$_m19_e24_toml" '^\s*cap_drop\s*=\s*\[\s*"ALL"\s*\]'
  check_cmd "$_m19_e24_rel : élévation de privilège interdite" \
    _m19p_toml_a "$_m19_e24_toml" '^\s*allow_privilege_escalation\s*=\s*false'
  check_cmd "$_m19_e24_rel : jamais de mode privilégié" bash -c '[[ -n "$1" ]] && ! grep -Eq "^\s*privileged\s*=\s*true" <<<"$1"' _ "$_m19_e24_toml"
  check_cmd "$_m19_e24_rel : pods de job en utilisateur non root, seccomp RuntimeDefault" bash -c \
    'grep -Eq "^\s*run_as_non_root\s*=\s*true" <<<"$1" && grep -Eq "^\s*type\s*=\s*\"RuntimeDefault\"" <<<"$1"' _ "$_m19_e24_toml"
done
check_cmd "gitlab-runner-protege : la clé cosign-medisphere est montée par ce runner" \
  _m19p_toml_a "$(_m19p_toml gitlab-runner-protege)" '^\s*name\s*=\s*"cosign-medisphere"'
check_cmd "gitlab-runner : aucun montage de la clé de signature dans les jobs ordinaires" \
  bash -c '[[ -n "$1" ]] && ! grep -q "cosign" <<<"$1"' _ "$(_m19p_toml gitlab-runner)"

title "Droits des gestionnaires"
check_cmd "gitlab-runner : droits par une Role de ci-jobs seulement, sans joker" \
  _m19p_role_minimale ci-jobs gitlab-runner "$_M19P_RUNNER_NS"
check_cmd "gitlab-runner-protege : droits par une Role de ci-jobs-protege seulement, sans joker" \
  _m19p_role_minimale ci-jobs-protege gitlab-runner-protege "$_M19P_RUNNER_NS"
for _m19_e24_sa in gitlab-runner gitlab-runner-protege; do
  check_cmd "aucun ClusterRoleBinding vers le compte $_M19P_RUNNER_NS/$_m19_e24_sa" _m19p_sans_crb "$_M19P_RUNNER_NS" "$_m19_e24_sa"
done
check_output "le gestionnaire ne lit pas les Secrets de mediagenda-dev" '^no$' \
  _m19p_peut "system:serviceaccount:$_M19P_RUNNER_NS:gitlab-runner" get secrets mediagenda-dev
check_output "le gestionnaire ne crée pas de pod dans kube-system" '^no$' \
  _m19p_peut "system:serviceaccount:$_M19P_RUNNER_NS:gitlab-runner" create pods kube-system

title "Politiques réseau"
for _m19_e24_ns in ci-jobs ci-jobs-protege; do
  check_cmd "$_m19_e24_ns : refus par défaut en entrée et en sortie" _m19p_jq "$(_m19p_json -n "$_m19_e24_ns" get networkpolicies)" \
    'any(.items[]; (.spec.podSelector | length) == 0 and (.spec.policyTypes | index("Ingress")) and (.spec.policyTypes | index("Egress")))'
  check_cmd "$_m19_e24_ns : politique de sortie Cilium sans ouverture vers tout le cluster" \
    _m19p_jq "$(_m19p_json -n "$_m19_e24_ns" get ciliumnetworkpolicies)" \
    '(.items | length) > 0 and all(.items[]; all(.spec.egress[]?; ((.toEntities // []) | (index("all") or index("cluster")) | not)))'
done
check_cmd "ci-jobs-protege : aucune sortie vers Internet" _m19p_jq "$(_m19p_json -n ci-jobs-protege get ciliumnetworkpolicies)" \
  '(.items | length) > 0 and all(.items[]; all(.spec.egress[]?; (((.toEntities // []) | index("world")) | not)
     and ([(.toCIDR // [])[], (.toCIDRSet // [])[].cidr] | index("0.0.0.0/0") | not)))'

title "Runner protégé (GitLab)"
_m19_e24_r="$(_m19p_runner "$_M19P_RUNNER_PROTEGE")"
check_cmd "le runner $_M19P_RUNNER_PROTEGE existe et est en ligne" _m19p_jq "$_m19_e24_r" '.status == "online" and (.paused | not)'
check_cmd "$_M19P_RUNNER_PROTEGE : références protégées seulement (ref_protected)" _m19p_jq "$_m19_e24_r" '.access_level == "ref_protected"'
check_cmd "$_M19P_RUNNER_PROTEGE : étiquette protege, aucun job sans étiquette" _m19p_jq "$_m19_e24_r" \
  '(.tag_list | index("protege")) and (.run_untagged == false)'

title "Jobs sensibles de mediagenda/api"
_m19_e24_pl="$(_m19p_pipeline_etiquette mediagenda/api)"
if [[ "$_m19_e24_pl" == null ]]; then
  check_cmd "mediagenda/api : un pipeline d'étiquette vX.Y.Z existe" false
else
  _m19_e24_jobs="$(_m19p_jobs mediagenda/api "$(jq -r .id <<<"$_m19_e24_pl")")"
  check_cmd "dernière étiquette ($(jq -r .ref <<<"$_m19_e24_pl")) : signature réussie sur $_M19P_RUNNER_PROTEGE" \
    _m19p_job_sur "$_m19_e24_jobs" securite:signature "$_M19P_RUNNER_PROTEGE"
  check_cmd "dernière étiquette : promotion vers dev réussie sur $_M19P_RUNNER_PROTEGE" \
    _m19p_jq "$_m19_e24_jobs" "any(.[]; (.name | test(\"^promotion\")) and .status == \"success\" and .runner.description == \"$_M19P_RUNNER_PROTEGE\")"
fi
_m19_e24_v="$(_m19p_variables projects mediagenda/api)"
check_cmd "mediagenda/api : aucune variable Cosign de projet" _m19p_jq "$_m19_e24_v" 'all(.[]; .key | test("COSIGN") | not)'
check_cmd "mediagenda/api : DEPLOIEMENT_TOKEN protégée et masquée" _m19p_jq "$_m19_e24_v" \
  'any(.[]; .key == "DEPLOIEMENT_TOKEN" and .protected and .masked)'

title "Documentation"
check_cmd "cloisonnement.md sur main (restricted, exceptions avec date de fin)" \
  _m19p_fichier_contient plateforme/medisphere docs/livraison/ci/cloisonnement.md 'restricted' 'exception' 'protege'
