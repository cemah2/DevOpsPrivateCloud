# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E07.sh — M20-E07 : AppProjects : cloisonner les équipes
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks : AppProjects, Applications, espaces),
# API GitLab en GET.

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E07 — AppProjects : cloisonner les équipes"
require_cmd jq kubectl

if ! _m20d_peut_lire_argo; then
  skip "Contrôles des AppProjects" "wb-checks ne lit pas encore les objets d'Argo CD : termine M20-E03"
  return 0
fi

# _m20d_e07_sources PROJET_JSON DEPOT — sourceRepos = exactement le dépôt donné (avec ou sans .git).
_m20d_e07_sources() {
  local n url
  n="$(jq -r '(.spec.sourceRepos // []) | length' <<<"$1" 2>/dev/null)" || return 1
  [[ "$n" == 1 ]] || return 1
  url="$(jq -r '.spec.sourceRepos[0]' <<<"$1")"
  _m20d_meme_depot "$url" "$2"
}
# _m20d_e07_destinations PROJET_JSON ESPACE… — destinations = exactement ces espaces, sur ce cluster.
_m20d_e07_destinations() {
  local projet="$1"
  shift
  _m20d_json "$projet" '
    [.spec.destinations[]? | {s: (.server // ""), n: (.namespace // ""), nom: (.name // "")}] as $d
    | ($d | length) == ($attendus | length)
    and all($d[]; (.s == $srv or .nom == "in-cluster") and (.n as $x | $attendus | index($x)))' \
    --arg srv "$_M20D_IN_CLUSTER" --argjson attendus "$(printf '%s\n' "$@" | jq -R . | jq -s .)"
}
_m20d_e07_equipe() {
  local p="$1" depot="$2"
  shift 2
  local j
  j="$(_m20d_projet "$p")"
  check_cmd "AppProject $p présent" _m20d_json "$j" '.kind == "AppProject"'
  check_cmd "$p : une seule source, $depot" _m20d_e07_sources "$j" "$depot"
  check_cmd "$p : destinations limitées à $*" _m20d_e07_destinations "$j" "$@"
  check_cmd "$p : aucun objet de cluster permis (clusterResourceWhitelist vide)" _m20d_json "$j" \
    '(.spec.clusterResourceWhitelist // []) | length == 0'
  check_cmd "$p : ResourceQuota et LimitRange interdits (gouvernés par plateforme/k8s)" _m20d_json "$j" \
    '[.spec.namespaceResourceBlacklist[]? | select((.group // "") == "") | .kind] as $k
     | ($k | index("ResourceQuota")) and ($k | index("LimitRange"))'
}

# --- 1. Projets des équipes ------------------------------------------------------------------------
_m20d_e07_equipe mediagenda mediagenda/deploiement mediagenda-dev mediagenda-recette mediagenda-prod
check_cmd "mediagenda : ressources orphelines signalées (warn)" _m20d_json "$(_m20d_projet mediagenda)" \
  '.spec.orphanedResources.warn == true'
_m20d_e07_equipe medidoc medidoc/deploiement medidoc-dev medidoc-recette
check_cmd "medidoc : ressources orphelines signalées (warn)" _m20d_json "$(_m20d_projet medidoc)" \
  '.spec.orphanedResources.warn == true'
_m20d_e07_equipe labo formation/gitops-labo wb-essais

# --- 2. Projet plateforme et projet default ---------------------------------------------------------
_m20d_e07_plat="$(_m20d_projet plateforme)"
check_cmd "AppProject plateforme : une seule source, plateforme/gitops" _m20d_e07_sources "$_m20d_e07_plat" plateforme/gitops
check_cmd "plateforme : l'espace argocd fait partie des destinations" _m20d_json "$_m20d_e07_plat" \
  '[.spec.destinations[]? | select(.namespace == "argocd")] | length >= 1'
check_cmd "plateforme : aucune destination joker (namespace « * »)" _m20d_json "$_m20d_e07_plat" \
  '[.spec.destinations[]? | select(.namespace == "*" or .server == "*")] | length == 0'
check_cmd "Projet default verrouillé (aucune source, aucune destination)" _m20d_json "$(_m20d_projet default)" \
  '((.spec.sourceRepos // []) | length == 0) and ((.spec.destinations // []) | length == 0)'

# --- 3. Les Applications sont rangées dans leurs projets --------------------------------------------
_m20d_e07_apps="$(_m20d_k -n "$_M20D_NS" get applications.argoproj.io -o json)"
check_cmd "Plus aucune Application dans le projet default" _m20d_json "$_m20d_e07_apps" \
  '.items | length > 0 and ([.[] | select(.spec.project == "default")] | length == 0)'
for _m20d_e07_a in racine:plateforme applications:plateforme projets:plateforme labo:labo; do
  check_cmd "Application ${_m20d_e07_a%%:*} : projet ${_m20d_e07_a##*:}, Synced" _m20d_json "$_m20d_e07_apps" \
    '[.items[] | select(.metadata.name == $a and .spec.project == $p and .status.sync.status == "Synced")] | length == 1' \
    --arg a "${_m20d_e07_a%%:*}" --arg p "${_m20d_e07_a##*:}"
done
_m20d_e07_projets="$(_m20d_app projets)"
check_cmd "Les AppProjects sont gérés depuis Git (Application projets, suivie par racine)" _m20d_json "$_m20d_e07_projets" \
  '.metadata.annotations["argocd.argoproj.io/tracking-id"] == "racine:argoproj.io/Application:argocd/projets"
   and .spec.source.path == "projets"'
for _m20d_e07_f in projets/plateforme.yaml projets/mediagenda.yaml projets/medidoc.yaml projets/labo.yaml projets/default.yaml racine/projets.yaml; do
  check_cmd "plateforme/gitops (main) : $_m20d_e07_f" _m20d_fichier_main plateforme/gitops "$_m20d_e07_f"
done

# --- 4. La production n'a plus d'objets gouvernés dans son overlay ----------------------------------
check_cmd "mediagenda-prod : l'espace est décrit dans plateforme/k8s (espaces/mediagenda-prod/)" \
  _m20d_fichier_main plateforme/k8s espaces/mediagenda-prod/00-namespace.yaml
_m20d_e07_prod() {
  local f
  f="$(_m20d_contenu_main mediagenda/deploiement overlays/prod/espace.yaml)"
  [[ -z "$f" ]] || ! grep -Eq '^kind:[[:space:]]*(Namespace|ResourceQuota|LimitRange)[[:space:]]*$' <<<"$f"
}
check_cmd "mediagenda/deploiement : overlays/prod ne crée plus Namespace, ResourceQuota ni LimitRange" _m20d_e07_prod
