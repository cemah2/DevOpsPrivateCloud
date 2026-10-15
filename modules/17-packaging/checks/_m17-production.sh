# shellcheck shell=bash
# _m17-production.sh — fonctions partagées par les vérifications des paliers 3 à 5 du module 17
# (check-E13 à check-E25). Sourcé par ces scripts, jamais lancé seul. Préfixe _m17p_.
#
# LECTURE SEULE. Exception documentée (énoncé du palier 3) : Helm range ses releases dans des Secrets,
# que le compte wb-checks ne lit pas. Les lectures d'état Helm (helm status/history/list/get, helmfile
# diff, kubectl diff --server-side, qui ne fait qu'une simulation) utilisent le kubeconfig
# personnel WB_K8S_ADMIN_KUBECONFIG (défaut ~/.kube/config). Aucune commande d'écriture n'est lancée.
#
# Rappel : lab/bin/check tourne avec « set -euo pipefail » : toute affectation par $(…) qui peut
# échouer est suivie de « || … ».

_m17p_src="${WB_SRC:-$HOME/src}"
_m17p_chart="$_m17p_src/mediagenda-chart"
_m17p_deploiement="$_m17p_src/mediagenda-deploiement"
_m17p_k8s="$_m17p_src/k8s"
_m17p_depot="${WB_DEPOT:-$HOME/medisphere}"
_m17p_harbor="${WB_HARBOR_URL:-https://registry.par1.medisphere.internal}"
_m17p_harbor_hote="${_m17p_harbor#https://}"
# Gestionnaires de champs qui trahissent un geste manuel (M17-E14, E18, E22).
# shellcheck disable=SC2034  # utilisée par les checks qui sourcent ce fichier
_m17p_manuels='^(kubectl-edit|kubectl-patch|kubectl-set|kubectl-client-side-apply|kubectl-label|kubectl-annotate)$'

_m17p_kubeconfig_admin() { printf '%s\n' "${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"; }

# _m17p_helm ARGS… — helm en lecture avec le kubeconfig personnel.
_m17p_helm() { helm --kubeconfig "$(_m17p_kubeconfig_admin)" "$@" 2>/dev/null; }

# _m17p_kadmin ARGS… — kubectl en LECTURE avec le kubeconfig personnel (Secrets de release seulement).
_m17p_kadmin() { kubectl --kubeconfig "$(_m17p_kubeconfig_admin)" --request-timeout="${WB_TIMEOUT}s" "$@" 2>/dev/null; }

# _m17p_rel_json ESPACE SECRET — révision Helm décodée (base64 de l'API, base64 de Helm, gzip).
_m17p_rel_json() {
  _m17p_kadmin get secret "$2" -n "$1" -o jsonpath='{.data.release}' | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gzip -dc 2>/dev/null
}

# _m17p_rel_statut ESPACE RELEASE — statut Helm de la release (vide si absente).
_m17p_rel_statut() { _m17p_helm status "$2" -n "$1" -o json | jq -r '.info.status // empty' 2>/dev/null; }

# _m17p_rel_chart ESPACE RELEASE — « nom-version » du chart de la release (helm list).
_m17p_rel_chart() {
  _m17p_helm list -n "$1" -o json | jq -r --arg r "$2" '.[] | select(.name == $r) | .chart' 2>/dev/null
}

# _m17p_rel_ssa ESPACE RELEASE — 0 si la dernière révision « deployed » est en server-side apply.
_m17p_rel_ssa() {
  local s
  s="$(_m17p_kadmin get secret -n "$1" -l "owner=helm,name=$2,status=deployed" -o json \
    | jq -r '[.items[] | {n: .metadata.name, v: (.metadata.labels.version | tonumber)}] | max_by(.v) | .n // empty' 2>/dev/null)" || s=""
  [[ -n "$s" ]] && _m17p_rel_json "$1" "$s" | jq -e '.apply_method == "ssa"' >/dev/null 2>&1
}

# --- GitLab -----------------------------------------------------------------
_m17p_enc() { jq -rn --arg s "$1" '$s | @uri'; }

# _m17p_gl_fichier PROJET CHEMIN [RÉF] — contenu brut d'un fichier (vide si absent).
_m17p_gl_fichier() {
  gitlab_api "projects/$(_m17p_enc "$1")/repository/files/$(_m17p_enc "$2")/raw?ref=${3:-main}" 2>/dev/null
}
_m17p_gl_existe() { [[ -n "$(_m17p_gl_fichier "$@" | head -c 1)" ]]; }

# _m17p_gl_arbre PROJET CHEMIN [RÉF] — noms des fichiers d'un dossier (récursif).
_m17p_gl_arbre() {
  gitlab_api "projects/$(_m17p_enc "$1")/repository/tree?path=$(_m17p_enc "$2")&ref=${3:-main}&recursive=true&per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null
}

# _m17p_gl_pipeline PROJET RÉF — dernier pipeline de la référence (JSON, vide si aucun).
_m17p_gl_pipeline() {
  gitlab_api "projects/$(_m17p_enc "$1")/pipelines?ref=$(_m17p_enc "$2")&per_page=1&order_by=id&sort=desc" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null
}

# _m17p_gl_pipeline_ok PROJET RÉF — 0 si le dernier pipeline de RÉF est « success ».
_m17p_gl_pipeline_ok() {
  _m17p_gl_pipeline "$1" "$2" | jq -e '.status == "success"' >/dev/null 2>&1
}

# _m17p_gl_jobs_ok PROJET RÉF REGEX… — 0 si le dernier pipeline de RÉF a, pour chaque regex, au moins
# un job réussi dont le nom correspond.
_m17p_gl_jobs_ok() {
  local p="$1" ref="$2" pid jobs r
  shift 2
  pid="$(_m17p_gl_pipeline "$p" "$ref" | jq -r '.id // empty' 2>/dev/null)" || pid=""
  [[ -n "$pid" ]] || return 1
  jobs="$(gitlab_api "projects/$(_m17p_enc "$p")/pipelines/$pid/jobs?per_page=100&include_retried=false" 2>/dev/null)" || return 1
  for r in "$@"; do
    jq -e --arg r "$r" '[.[] | select(.status == "success" and (.name | test($r; "i")))] | length > 0' >/dev/null 2>&1 <<<"$jobs" || return 1
  done
}

# _m17p_gl_derniere_version PROJET — plus haute étiquette vX.Y.Z (sans le « v »), vide si aucune.
_m17p_gl_derniere_version() {
  gitlab_api "projects/$(_m17p_enc "$1")/repository/tags?search=%5Ev&per_page=100" 2>/dev/null \
    | jq -r '.[].name' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n1
}

# --- Harbor -----------------------------------------------------------------
# _m17p_harbor_artefact PROJET DÉPÔT ÉTIQUETTE — JSON de l'artefact portant l'étiquette (vide sinon).
_m17p_harbor_artefact() {
  harbor_api "projects/$1/repositories/$(_m17p_enc "$2" | sed 's/%2F/%252F/g')/artifacts?with_tag=true&with_accessory=true&page_size=100&q=$(_m17p_enc "tags=$3")" 2>/dev/null \
    | jq -c --arg t "$3" '[.[] | select([.tags[]?.name] | index($t))][0] // empty' 2>/dev/null
}

# _m17p_cosign_ok RÉF@DIGEST — 0 si la signature MédiSphère se vérifie (sans journal de transparence).
# Identifiants : robot de lecture des checks, dans une configuration Docker temporaire (jamais en argument).
# Renvoie 2 si la vérification est impossible ici (cosign, clé publique ou identifiants absents).
_m17p_cosign_ok() {
  local ref="$1" cle="$_m17p_depot/docs/registre/cosign.pub" f="${WB_HARBOR_CHECKS_FILE:-$HOME/.config/workbook/harbor-checks.env}" d rc=0
  local HARBOR_USER="" HARBOR_PASSWORD=""
  command -v cosign >/dev/null 2>&1 && [[ -r "$cle" && -r "$f" ]] || return 2
  # shellcheck disable=SC1090
  source "$f"
  d="$(mktemp -d)" || return 2
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$_m17p_harbor_hote" "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" >"$d/config.json"
  chmod 600 "$d/config.json"
  DOCKER_CONFIG="$d" timeout 60 cosign verify --key "$cle" --insecure-ignore-tlog=true "$ref" >/dev/null 2>&1 || rc=1
  rm -rf -- "$d"
  return "$rc"
}

# --- Objets Kubernetes ----------------------------------------------------------
# _m17p_deploy ESPACE NOM — Deployment en JSON (compte wb-checks), managedFields compris.
_m17p_deploy() { kube get deploy "$2" -n "$1" --show-managed-fields -o json 2>/dev/null; }

# _m17p_jq JSON 'filtre' — 0 si le filtre est vrai sur le document.
_m17p_jq() { jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# _m17p_sans_manuel JSON — 0 si aucun gestionnaire de geste manuel ne possède de champ de l'objet.
_m17p_sans_manuel() {
  jq -e --arg r "$_m17p_manuels" '[.metadata.managedFields[]? | select(.manager | test($r))] | length == 0' >/dev/null 2>&1 <<<"$1"
}

# _m17p_deploy_a_jour JSON — 0 si le déploiement est terminé et tous les pods sont prêts.
_m17p_deploy_a_jour() {
  jq -e '(.status.observedGeneration // 0) >= .metadata.generation
         and (.spec.replicas // 1) > 0
         and (.status.updatedReplicas // 0) == (.spec.replicas // 1)
         and (.status.readyReplicas // 0) == (.spec.replicas // 1)
         and (.status.replicas // 0) == (.spec.replicas // 1)' >/dev/null 2>&1 <<<"$1"
}

# _m17p_image_tag JSON — étiquette de l'image du conteneur « api ».
_m17p_image_tag() {
  jq -r '.spec.template.spec.containers[] | select(.name == "api") | .image' 2>/dev/null <<<"$1" | sed -E 's/@sha256:.*//; s/.*:([^:/]+)$/\1/'
}

# _m17p_env JSON VARIABLE — valeur littérale de la variable dans le conteneur « api » (vide sinon).
_m17p_env() {
  jq -r --arg v "$2" '.spec.template.spec.containers[] | select(.name == "api") | .env[]? | select(.name == $v) | .value // empty' 2>/dev/null <<<"$1"
}

# --- Copies de travail ------------------------------------------------------------
# _m17p_exporter DÉPÔT RÉF DOSSIER — copie l'arbre de RÉF (sans toucher à la copie de travail).
_m17p_exporter() {
  git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null 2>&1 || return 1
  git -C "$1" archive "$2" 2>/dev/null | tar -x -C "$3" 2>/dev/null
}

# _m17p_ref_principale DÉPÔT — origin/main s'il existe, sinon main.
_m17p_ref_principale() {
  if git -C "$1" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then echo origin/main; else echo main; fi
}

# _m17p_diff_overlay ENV — 0 si « kubectl diff --server-side -k overlays/ENV » (rendu de origin/main)
# est vide. Simulation côté serveur : rien n'est écrit.
_m17p_diff_overlay() {
  local d rc=0 ref
  ref="$(_m17p_ref_principale "$_m17p_deploiement")"
  d="$(mktemp -d)" || return 1
  if _m17p_exporter "$_m17p_deploiement" "$ref" "$d" && [[ -d "$d/overlays/$1" ]]; then
    _m17p_kadmin diff --server-side -k "$d/overlays/$1" >/dev/null || rc=$?
  else
    rc=3
  fi
  rm -rf -- "$d"
  ((rc == 0))
}

# _m17p_helmfile_diff_vide — 0 si « helmfile -e par1 diff » est vide sur l'arbre de origin/main de
# ~/src/k8s (copie exportée : la copie de travail n'est pas utilisée). Dépôts Helm déjà configurés.
_m17p_helmfile_diff_vide() {
  local d rc=0 ref
  command -v helmfile >/dev/null 2>&1 || return 2
  ref="$(_m17p_ref_principale "$_m17p_k8s")"
  d="$(mktemp -d)" || return 1
  if _m17p_exporter "$_m17p_k8s" "$ref" "$d" && [[ -f "$d/helmfile.yaml" ]]; then
    (cd "$d" && timeout 600 helmfile --kubeconfig "$(_m17p_kubeconfig_admin)" -e par1 diff \
      --skip-deps --detailed-exitcode --suppress-secrets >/dev/null 2>&1) || rc=$?
  else
    rc=3
  fi
  rm -rf -- "$d"
  ((rc == 0))
}

# _m17p_panne_close EXX… — aucune des pannes listées n'est marquée active.
_m17p_panne_close() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  for e in "$@"; do
    [[ ! -e "$d/M17-$e" ]] || return 1
  done
}
