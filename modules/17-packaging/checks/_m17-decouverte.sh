# shellcheck shell=bash
# _m17-decouverte.sh — fonctions partagées par les vérifications des paliers 1 et 2 du module 17
# (check-E02 à check-E12). Sourcé par ces scripts, jamais lancé seul. Préfixe _m17d_.
#
# LECTURE SEULE : le cluster est lu avec le compte wb-checks (fonction kube de check-lib.sh), qui ne
# lit PAS les Secrets, donc pas l'historique Helm : l'appartenance à une release se lit dans les
# annotations meta.helm.sh/* et l'étiquette helm.sh/chart des objets. GitLab et Harbor sont lus avec
# les jetons en lecture des checks. Les rendus de chart (helm lint, helm template, helm unittest) se
# font sur une copie de origin/main extraite dans un répertoire temporaire, supprimé à la fin.
#
# Rappel : lab/bin/check tourne avec « set -euo pipefail » : toute affectation par $(…) qui peut
# échouer est suivie de « || … ».

_m17d_src="${WB_SRC:-$HOME/src}"
_m17d_chart_clone="$_m17d_src/mediagenda-chart"
_m17d_deploiement_clone="$_m17d_src/mediagenda-deploiement"
_m17d_k8s_clone="$_m17d_src/k8s"
_m17d_brouillons="$HOME/m17"
_m17d_domaine="apps.par1.medisphere.internal"
# Répertoire temporaire du check, créé ici (dans le shell principal : une affectation faite dans
# une substitution $(…) serait perdue) et supprimé à la sortie.
_m17d_tmp="$(mktemp -d)"
_m17d_nettoyer() { [[ -n "$_m17d_tmp" && -d "$_m17d_tmp" ]] && rm -rf "$_m17d_tmp"; return 0; }
trap _m17d_nettoyer EXIT

_m17d_tmpdir() { printf '%s\n' "$_m17d_tmp"; }

# --- Cluster (wb-checks) ------------------------------------------------------------------------
# _m17d_obj ESPACE TYPE NOM — objet en JSON (vide si absent ou illisible).
_m17d_obj() { kube get "$2" "$3" -n "$1" -o json 2>/dev/null || true; }

# _m17d_liste ESPACE TYPE [SÉLECTEUR] — liste JSON (vide si erreur).
_m17d_liste() {
  if [[ -n "${3:-}" ]]; then kube get "$2" -n "$1" -l "$3" -o json 2>/dev/null || true
  else kube get "$2" -n "$1" -o json 2>/dev/null || true; fi
}

# _m17d_jq JSON FILTRE — 0 si le filtre jq est vrai.
_m17d_jq() { [[ -n "$1" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# _m17d_de_release JSON RELEASE — l'objet appartient à la release Helm (annotations de Helm).
_m17d_de_release() {
  [[ -n "$1" ]] && jq -e --arg r "$2" '.metadata.annotations["meta.helm.sh/release-name"] == $r' >/dev/null 2>&1 <<<"$1"
}

# _m17d_hors_helm JSON — l'objet n'appartient à aucune release Helm.
_m17d_hors_helm() {
  [[ -n "$1" ]] && jq -e '(.metadata.annotations // {}) | has("meta.helm.sh/release-name") | not' >/dev/null 2>&1 <<<"$1"
}

# _m17d_pret JSON [MIN] — Deployment/StatefulSet : au moins MIN réplicas prêts (défaut 1) et autant
# que demandé.
_m17d_pret() {
  [[ -n "$1" ]] && jq -e --argjson m "${2:-1}" \
    '(.status.readyReplicas // 0) >= $m and (.status.readyReplicas // 0) >= (.spec.replicas // 1)' >/dev/null 2>&1 <<<"$1"
}

# _m17d_restricted JSON — gabarit de pod conforme aux points clés de Pod Security « restricted ».
_m17d_restricted() {
  [[ -n "$1" ]] && jq -e '.spec.template.spec as $p
    | ($p.securityContext.runAsNonRoot == true or ([$p.containers[] | .securityContext.runAsNonRoot == true] | all))
    and (($p.securityContext.seccompProfile.type // "") == "RuntimeDefault"
         or ([$p.containers[] | (.securityContext.seccompProfile.type // "") == "RuntimeDefault"] | all))
    and ([$p.containers[], ($p.initContainers // [])[] | .securityContext.allowPrivilegeEscalation == false
          and ((.securityContext.capabilities.drop // []) | index("ALL") != null)] | all)' >/dev/null 2>&1 <<<"$1"
}

# _m17d_route_acceptee JSON — HTTPRoute acceptée par au moins un parent, références résolues.
_m17d_route_acceptee() {
  _m17d_jq "$1" '[.status.parents[]?.conditions[]? | select(.type == "Accepted" and .status == "True")] | length > 0' \
    && _m17d_jq "$1" '[.status.parents[]?.conditions[]? | select(.type == "ResolvedRefs" and .status == "False")] | length == 0'
}

# _m17d_version_chart JSON — version du chart lue dans l'étiquette helm.sh/chart (« mediagenda-0.5.0 »).
_m17d_version_chart() {
  jq -r '.metadata.labels["helm.sh/chart"] // ""' <<<"$1" 2>/dev/null | sed -n 's/^mediagenda-\([0-9][0-9.]*\).*/\1/p'
}

# _m17d_version_ge A B — 0 si la version A >= B (SemVer simple).
_m17d_version_ge() {
  [[ -n "$1" ]] && [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

# _m17d_sante URL [VERSION] — /sante répond 200 (et annonce VERSION si donnée).
_m17d_sante() {
  local corps
  corps="$(curl -fsS --max-time "$WB_TIMEOUT" "$1" 2>/dev/null)" || return 1
  [[ -z "${2:-}" ]] && return 0
  jq -e --arg v "$2" '.version == $v' >/dev/null 2>&1 <<<"$corps"
}

# --- GitLab -------------------------------------------------------------------------------------
_m17d_enc() { jq -rn --arg s "$1" '$s | @uri'; }

# _m17d_gl_fichier PROJET CHEMIN [RÉF] — contenu brut (vide si absent).
_m17d_gl_fichier() {
  gitlab_api "projects/$(_m17d_enc "$1")/repository/files/$(_m17d_enc "$2")/raw?ref=${3:-main}" 2>/dev/null || true
}
_m17d_gl_existe() { [[ -n "$(_m17d_gl_fichier "$@" | head -c 1)" ]]; }

# _m17d_gl_arbre PROJET CHEMIN — chemins des fichiers d'un dossier de main (récursif).
_m17d_gl_arbre() {
  gitlab_api "projects/$(_m17d_enc "$1")/repository/tree?path=$(_m17d_enc "$2")&ref=main&recursive=true&per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# --- Copies de origin/main ------------------------------------------------------------------------
# _m17d_extraire CLONE CHEMIN — extrait CHEMIN de origin/main du clone dans un répertoire temporaire
# et affiche ce répertoire (vide si impossible). git archive ne modifie pas le clone.
_m17d_extraire() {
  local clone="$1" chemin="$2" dest
  [[ -d "$clone/.git" ]] || return 0
  dest="$(_m17d_tmpdir)/$(basename "$clone")"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "$dest"
    git -C "$clone" archive "origin/main" -- "$chemin" 2>/dev/null | tar -x -C "$dest" 2>/dev/null || return 0
  fi
  [[ -e "$dest/$chemin" ]] && printf '%s\n' "$dest"
}

# _m17d_chart_main — répertoire temporaire contenant charts/ de origin/main de mediagenda/chart, avec
# les dépendances reconstruites depuis Chart.lock (helm dependency build : téléchargement seul, avec
# la connexion au registre de l'utilisateur). Vide si impossible.
_m17d_chart_main() {
  local d
  d="$(_m17d_extraire "$_m17d_chart_clone" charts)" || d=""
  [[ -n "$d" ]] || return 0
  if [[ ! -f "$d/.deps" ]]; then
    if grep -q '^dependencies:' "$d/charts/mediagenda/Chart.yaml" 2>/dev/null; then
      helm dependency build "$d/charts/mediagenda" >/dev/null 2>&1 || true
    fi
    : >"$d/.deps"
  fi
  printf '%s\n' "$d/charts/mediagenda"
}

# _m17d_rendu CHART ARGS… — helm template de la release « mediagenda » (sortie, vide si échec).
_m17d_rendu() {
  local c="$1"; shift
  helm template mediagenda "$c" -n mediagenda-dev "$@" 2>/dev/null || true
}

# _m17d_rendu_refuse CHART ARGS… — 0 si le rendu ÉCHOUE (règle de validation qui fonctionne).
_m17d_rendu_refuse() {
  local c="$1"; shift
  ! helm template mediagenda "$c" -n mediagenda-dev "$@" >/dev/null 2>&1
}

# --- Harbor -------------------------------------------------------------------------------------
# _m17d_harbor_signe DÉPÔT ÉTIQUETTE — l'artefact charts/DÉPÔT:ÉTIQUETTE existe et a au moins un
# accessoire (signature Cosign) attaché.
_m17d_harbor_signe() {
  harbor_api "projects/charts/repositories/$1/artifacts?with_tag=true&with_accessory=true&page_size=100" 2>/dev/null \
    | jq -e --arg t "$2" '[.[] | select([.tags[]?.name] | index($t)) | (.accessories // []) | length] | any(. > 0)' >/dev/null 2>&1
}

# _m17d_fichier_contient FICHIER REGEX — fichier local présent qui contient la regex (étendue).
_m17d_fichier_contient() { [[ -s "$1" ]] && grep -Eq -- "$2" "$1"; }
