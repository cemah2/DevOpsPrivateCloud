# shellcheck shell=bash
# _m19-production.sh — fonctions partagées par les checks M19-E24 à M19-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_K8S_KUBECONFIG (via kube), WB_GITLAB_URL et
# WB_GITLAB_TOKEN_FILE (via gitlab_api : jeton read_api + admin_mode des checks, M01),
# WB_HARBOR_URL et WB_HARBOR_CHECKS_FILE (via harbor_api), WB_MOI, WB_TIMEOUT.
# Accès : « kube » (compte de service wb-checks : lecture, jamais les Secrets ; SubjectAccessReview
# pour vérifier des droits), GitLab et Harbor en GET. L'API des variables de GitLab renvoie les
# valeurs : elles sont RETIRÉES par jq dès la réception (_m19p_variables) et jamais affichées.

_M19P_RUNNER_NS=gitlab-runner
_M19P_RUNNER=k8s-par1
_M19P_RUNNER_PROTEGE=k8s-par1-protege
# Comptes humains (personnages et apprenant) : un pipeline planifié de plateforme ne leur appartient pas.
_M19P_HUMAINS="root claire.morel karim.benali sophie.laurent julien.petit nadia.roussel lucas.martin ${WB_MOI:-}"

# --- Utilitaires JSON ------------------------------------------------------------------------------

# _m19p_jq JSON FILTRE — filtre booléen jq sur un document (null ou vide → faux).
_m19p_jq() { [[ -n "$1" && "$1" != null ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# _m19p_json ARGS… — sortie JSON valide de « kube ARGS -o json », ou « null ».
_m19p_json() {
  local s
  s="$(kube "$@" -o json 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m19p_gl CHEMIN — GET GitLab, JSON valide ou « null ».
_m19p_gl() {
  local s
  s="$(gitlab_api "$1" 2>/dev/null)" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m19p_p CHEMIN — chemin de projet ou de groupe encodé pour l'API (a/b → a%2Fb).
_m19p_p() { printf '%s' "${1//\//%2F}"; }

# _m19p_age_s DATE_ISO — secondes écoulées depuis DATE_ISO (vide si illisible).
_m19p_age_s() {
  local t
  t="$(date -d "$1" +%s 2>/dev/null)" || return 0
  echo $(( $(date +%s) - t ))
}

# --- Kubernetes ------------------------------------------------------------------------------------

# _m19p_toml RELEASE — configuration TOML du runner (ConfigMap du chart, clé config.template.toml).
_m19p_toml() {
  kube -n "$_M19P_RUNNER_NS" get configmap "$1" -o jsonpath='{.data.config\.template\.toml}' 2>/dev/null || true
}

# _m19p_toml_global RELEASE — partie globale de la configuration (clé config.toml de la ConfigMap du
# chart : concurrent, check_interval, shutdown_timeout ; les [[runners]] sont dans config.template.toml).
_m19p_toml_global() {
  kube -n "$_M19P_RUNNER_NS" get configmap "$1" -o jsonpath='{.data.config\.toml}' 2>/dev/null || true
}

# _m19p_toml_a TOML REGEX — la configuration contient une ligne (hors commentaire) qui correspond.
_m19p_toml_a() { grep -v '^[[:space:]]*#' <<<"$1" | grep -Eq -- "$2"; }

# _m19p_peut COMPTE VERBE RESSOURCE ESPACE — « yes »/« no » d'une SubjectAccessReview
# (COMPTE = system:serviceaccount:<espace>:<nom>). Rien n'est écrit dans le cluster.
_m19p_peut() {
  local r ns="${1#system:serviceaccount:}"
  ns="${ns%%:*}"
  r="$(kube create -o json -f - 2>/dev/null <<EOF
{"apiVersion":"authorization.k8s.io/v1","kind":"SubjectAccessReview",
 "spec":{"user":"$1","groups":["system:serviceaccounts","system:serviceaccounts:$ns","system:authenticated"],
  "resourceAttributes":{"verb":"$2","resource":"$3","namespace":"$4"}}}
EOF
)" || r=""
  if jq -e '.status.allowed == true' >/dev/null 2>&1 <<<"$r"; then echo yes; elif [[ -n "$r" ]]; then echo no; else echo erreur; fi
}

# _m19p_role_minimale ESPACE COMPTE_SA ESPACE_SA — le compte n'a, dans ESPACE, que des Roles sans
# joker (verbes et ressources) ; renvoie faux s'il n'en a aucune.
_m19p_role_minimale() {
  local rb roles r n=0
  rb="$(_m19p_json -n "$1" get rolebindings)"
  roles="$(jq -r --arg sa "$2" --arg ns "$3" '.items[]? | select(any(.subjects[]?; .kind == "ServiceAccount" and .name == $sa and (.namespace // "") == $ns)) | "\(.roleRef.kind)/\(.roleRef.name)"' <<<"$rb" 2>/dev/null)" || roles=""
  [[ -n "$roles" ]] || return 1
  while read -r r; do
    [[ "$r" == Role/* ]] || return 1
    _m19p_jq "$(_m19p_json -n "$1" get role "${r#Role/}")" \
      'all(.rules[]; (.verbs | index("*") | not) and (.resources | index("*") | not))' || return 1
    n=$((n + 1))
  done <<<"$roles"
  (( n > 0 ))
}

# _m19p_sans_crb ESPACE_SA COMPTE_SA — aucun ClusterRoleBinding ne cite ce compte de service.
_m19p_sans_crb() {
  local c
  c="$(_m19p_json get clusterrolebindings)"
  [[ "$c" != null ]] && ! jq -e --arg sa "$2" --arg ns "$1" \
    'any(.items[]; any(.subjects[]?; .kind == "ServiceAccount" and .name == $sa and .namespace == $ns))' >/dev/null <<<"$c"
}

# --- GitLab : runners ------------------------------------------------------------------------------

# _m19p_runner DESCRIPTION — JSON détaillé du runner d'instance de cette description, ou null.
_m19p_runner() {
  local id
  id="$(_m19p_gl "runners/all?type=instance_type&per_page=100" \
    | jq -r --arg d "$1" '[.[]? | select(.description == $d)] | first | .id // empty' 2>/dev/null)" || id=""
  if [[ -n "$id" ]]; then _m19p_gl "runners/$id"; else echo null; fi
}

# _m19p_gestionnaires ID — gestionnaires (runner managers) du runner.
_m19p_gestionnaires() { _m19p_gl "runners/$1/managers"; }

# --- GitLab : pipelines et jobs ---------------------------------------------------------------------

# _m19p_pipeline_main PROJET — dernier pipeline de main (JSON), ou null.
_m19p_pipeline_main() { _m19p_gl "projects/$(_m19p_p "$1")/pipelines?ref=main&per_page=1" | jq -c '.[0] // null' 2>/dev/null || echo null; }

# _m19p_pipeline_etiquette PROJET [REGEX] — dernier pipeline d'étiquette (ref ~ REGEX, défaut vX.Y.Z).
_m19p_pipeline_etiquette() {
  local re="${2:-^v[0-9]+\\.[0-9]+\\.[0-9]+$}"
  _m19p_gl "projects/$(_m19p_p "$1")/pipelines?scope=tags&per_page=20&order_by=id&sort=desc" \
    | jq -c --arg re "$re" '[.[]? | select(.ref | test($re))] | first // null' 2>/dev/null || echo null
}

# _m19p_pipeline_mr PROJET — dernier pipeline de merge request (JSON), ou null.
_m19p_pipeline_mr() {
  _m19p_gl "projects/$(_m19p_p "$1")/pipelines?source=merge_request_event&per_page=1" | jq -c '.[0] // null' 2>/dev/null || echo null
}

# _m19p_jobs PROJET ID_PIPELINE — jobs du pipeline (sans les relances).
_m19p_jobs() { _m19p_gl "projects/$(_m19p_p "$1")/pipelines/$2/jobs?per_page=100"; }

# _m19p_job_sur JOBS NOM RUNNER — le job NOM a réussi sur le runner de description RUNNER.
_m19p_job_sur() {
  _m19p_jq "$1" "any(.[]; .name == \"$2\" and .status == \"success\" and (.runner.description // \"\") == \"$3\")"
}

# _m19p_lint PROJET — réponse de GET ci/lint (configuration fusionnée de la branche par défaut).
_m19p_lint() { _m19p_gl "projects/$(_m19p_p "$1")/ci/lint"; }

# _m19p_seulement_composants LINT — tous les includes sont des composants (ou des fichiers locaux).
_m19p_seulement_composants() {
  _m19p_jq "$1" '.valid == true and (.includes | length) > 0 and all(.includes[]; .type == "component" or .type == "local")'
}

# _m19p_inclut_composant LINT NOM VERSION_MIN — composant plateforme/ci-templates/NOM inclus en
# version ≥ VERSION_MIN (X.Y.Z, « v » facultatif).
_m19p_inclut_composant() {
  _m19p_jq "$1" "any(.includes[]?; .type == \"component\"
    and (.location | test(\"plateforme/ci-templates/$2@v?[0-9]+\\\\.[0-9]+\\\\.[0-9]+\$\"))
    and ((.location | capture(\"@v?(?<v>[0-9]+\\\\.[0-9]+\\\\.[0-9]+)\$\").v | split(\".\") | map(tonumber))
         >= (\"$3\" | split(\".\") | map(tonumber))))"
}

# _m19p_variables PORTEE ID — variables (sans leurs valeurs) d'un projet ou d'un groupe
# (PORTEE = projects | groups).
_m19p_variables() {
  local s
  s="$(gitlab_api "$1/$(_m19p_p "$2")/variables?per_page=100" 2>/dev/null | jq -c 'map(del(.value))' 2>/dev/null)" || s=""
  [[ -n "$s" ]] && printf '%s\n' "$s" || echo null
}

# _m19p_issues_ouvertes PROJET ETIQUETTE — nombre de tickets ouverts portant l'étiquette
# (« illisible » si l'API ne répond pas : jamais 0 par défaut).
_m19p_issues_ouvertes() {
  _m19p_gl "projects/$(_m19p_p "$1")/issues?state=opened&labels=$2&per_page=100" \
    | jq -r 'if type == "array" then length else "illisible" end' 2>/dev/null || echo illisible
}

# --- GitLab : fichiers des dépôts --------------------------------------------------------------------

# _m19p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m19p_fichier_main() { gitlab_api "projects/$(_m19p_p "$1")/repository/files/$(_m19p_p "$2")/raw?ref=main"; }

# _m19p_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif.
_m19p_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m19p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m19p_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
_m19p_arbre() {
  gitlab_api "projects/$(_m19p_p "$1")/repository/tree?ref=main&path=$(_m19p_p "$2")&recursive=true&per_page=100" 2>/dev/null \
    | jq -r '.[]? | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m19p_doc_prefixe PROJET DOSSIER PRÉFIXE REGEX… — un fichier dont le nom commence par PRÉFIXE,
# n'importe où sous DOSSIER (main), contient chaque motif.
_m19p_doc_prefixe() {
  local p="$1" d="$2" pre="$3" f
  shift 3
  f="$(_m19p_arbre "$p" "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -1)" || f=""
  [[ -n "$f" ]] || return 1
  _m19p_fichier_contient "$p" "$f" "$@"
}

# --- Harbor -------------------------------------------------------------------------------------------

# _m19p_artefact_version PROJET DEPOT [REGEX] — dernier artefact poussé portant une étiquette ~ REGEX
# (défaut vX.Y.Z), avec ses accessoires (signatures, attestations), ou null.
_m19p_artefact_version() {
  local re="${3:-^v[0-9]+\\.[0-9]+\\.[0-9]+$}" d="${2//\//%252F}"
  harbor_api "projects/$1/repositories/$d/artifacts?with_tag=true&with_accessory=true&page_size=30&sort=-push_time" 2>/dev/null \
    | jq -c --arg re "$re" '[.[]? | select(any(.tags[]?; .name | test($re)))] | first // null' 2>/dev/null || echo null
}

# _m19p_signee_attestee ARTEFACT — au moins trois accessoires Cosign : la signature et les deux
# attestations (SBOM, provenance). Harbor 2.15.3 range TOUS les bundles Sigstore de Cosign 3
# (référents d'artifactType application/vnd.dev.sigstore.bundle.v0.3+json, signature comme
# attestation) sous le type « signature.cosign » (src/server/middleware/subject/subject.go) :
# on ne compte donc que ce type, pas le SBOM que Harbor génère lui-même (« sbom.harbor »).
_m19p_signee_attestee() {
  _m19p_jq "$1" '[.accessories[]? | select(.type == "signature.cosign")] | length >= 3'
}
