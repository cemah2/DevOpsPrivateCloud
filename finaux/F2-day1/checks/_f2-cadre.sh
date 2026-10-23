# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f2-cadre.sh — fonctions partagées par les vérifications des phases 1 et 2 du final F2 (check-S01 à
# check-S06). Sourcé, jamais lancé seul. Préfixe _f2a_ : évite les collisions quand la recette (S13)
# charge plusieurs fichiers de fonctions.
#
# Lecture seule : GitLab en GET (jeton des checks), « kube » (compte wb-checks, jamais les Secrets),
# annuaire en LDAP (compte système wb-checks), OpenBao (AppRole wb-checks : métadonnées seulement),
# Backstage (jeton du catalogue), Grafana (Viewer), Alertmanager (API v2), Harbor (robot en lecture).
#
# Variables (lab/lab.env, facultatives) : WB_F2_DOC, WB_F2_PROJET_EQUIPES, WB_F2_EQUIPES, WB_F2_PROJET_CODE,
# WB_F2_PROJET_DEPLOIEMENT, WB_F2_COMPOSANT, WB_F2_IMAGE, WB_F2_DEPLOIEMENT, WB_F2_URL_DEV,
# WB_F2_URL_RECETTE, WB_F2_URL_PROD ; et celles du bloc G (WB_GITLAB_*, WB_K8S_KUBECONFIG, …).

_F2A_DOC="${WB_F2_DOC:-docs/accueil}"
_F2A_P_EQUIPES="${WB_F2_PROJET_EQUIPES:-plateforme/equipes}"
_F2A_EQUIPES="${WB_F2_EQUIPES:-medivisio data}"
_F2A_P_CODE="${WB_F2_PROJET_CODE:-medivisio/consultation}"
_F2A_P_DEPLOIEMENT="${WB_F2_PROJET_DEPLOIEMENT:-medivisio/consultation-deploiement}"
_F2A_COMPOSANT="${WB_F2_COMPOSANT:-medivisio-consultation}"
_F2A_IMAGE="${WB_F2_IMAGE:-medisphere/medivisio-consultation}"
_F2A_DEPLOIEMENT="${WB_F2_DEPLOIEMENT:-consultation}"
_F2A_URL_DEV="${WB_F2_URL_DEV:-https://consultation-dev.apps.par1.medisphere.internal}"
_F2A_URL_RECETTE="${WB_F2_URL_RECETTE:-https://consultation-recette.apps.par1.medisphere.internal}"
_F2A_URL_PROD="${WB_F2_URL_PROD:-https://consultation.apps.par1.medisphere.internal}"
_F2A_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

# --- Outils génériques --------------------------------------------------------------------------------

_f2a_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f2a_json 'JSON' 'filtre jq' — vrai si le filtre rend vrai (jq -e) sur le JSON donné.
_f2a_json() { [[ -n "$1" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# --- GitLab (lecture) ---------------------------------------------------------------------------------

# _f2a_fichier PROJET CHEMIN [RÉF=main] — contenu du fichier (vide si absent).
_f2a_fichier() {
  gitlab_api "projects/$(_f2a_enc "$1")/repository/files/$(_f2a_enc "$2")/raw?ref=$(_f2a_enc "${3:-main}")" 2>/dev/null || true
}

# _f2a_arbre PROJET [DOSSIER] — chemins des fichiers sous DOSSIER (main, récursif, 1 000 au plus).
_f2a_arbre() {
  local p page=1 r
  p="$(_f2a_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(_f2a_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f2a_contient 'TEXTE' REGEX… — chaque motif (ERE, insensible à la casse) apparaît dans le texte.
_f2a_contient() {
  local t="$1" m
  shift
  [[ -n "$t" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$t" || return 1; done
}

# _f2a_doc MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous docs/accueil (récursif, main) dont
# le NOM correspond à MOTIF_NOM contient chaque motif.
_f2a_doc() {
  local motif="$1" f
  shift
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f2a_contient "$(_f2a_fichier plateforme/medisphere "$f")" "$@" && return 0
  done < <(_f2a_arbre plateforme/medisphere "$_F2A_DOC")
  return 1
}

# _f2a_doc_present MOTIF_NOM — au moins un fichier de docs/accueil dont le nom correspond.
_f2a_doc_present() {
  _f2a_arbre plateforme/medisphere "$_F2A_DOC" | awk -F/ '{print $NF}' | grep -Eq -- "$1"
}

# _f2a_projet_existe PROJET
_f2a_projet_existe() { gitlab_api "projects/$(_f2a_enc "$1")" >/dev/null 2>&1; }

# _f2a_niveau_membre GROUPE IDENTIFIANT — niveau d'accès DIRECT de la personne dans le groupe (0 si absente).
_f2a_niveau_membre() {
  local g
  g="$(gitlab_api "groups/$(_f2a_enc "$1")/members?per_page=100" 2>/dev/null)" || { echo 0; return 0; }
  jq -r --arg u "$2" '[.[]? | select(.username == $u) | .access_level] | max // 0' <<<"$g"
}

# --- Kubernetes (compte wb-checks) --------------------------------------------------------------------

# _f2a_k JSON… — kube … -o json, vide en cas d'erreur.
_f2a_k() { kube "$@" -o json 2>/dev/null || true; }

# _f2a_apps_vers ESPACE — Applications Argo CD dont la destination est ESPACE (JSON : tableau).
_f2a_apps_vers() {
  _f2a_k -n argocd get applications.argoproj.io | jq -c --arg ns "$1" '[.items[]? | select(.spec.destination.namespace == $ns)]' 2>/dev/null || echo '[]'
}

# _f2a_app_saine ESPACE [REGEX_DÉPÔT] — une Application vers ESPACE (dont la source correspond au motif,
# si donné) est Synced et Healthy.
_f2a_app_saine() {
  local a
  a="$(_f2a_apps_vers "$1")"
  jq -e --arg r "${2:-.}" 'any(.[]; ((.spec.source.repoURL // .spec.sources[0].repoURL // "") | test($r))
    and .status.sync.status == "Synced" and .status.health.status == "Healthy")' >/dev/null 2>&1 <<<"$a"
}

# _f2a_deploy ESPACE — JSON du Deployment du service (nom WB_F2_DEPLOIEMENT), vide s'il manque.
_f2a_deploy() { kube -n "$1" get deployment "$_F2A_DEPLOIEMENT" -o json 2>/dev/null || true; }

# _f2a_deploy_pret 'JSON' [MIN=1] — rollout terminé (generation observée, réplicas à jour et prêts ≥ MIN).
_f2a_deploy_pret() {
  _f2a_json "$1" "(.status.observedGeneration // 0) >= .metadata.generation
    and (.status.updatedReplicas // 0) == .spec.replicas
    and (.status.availableReplicas // 0) == .spec.replicas
    and (.status.unavailableReplicas // 0) == 0
    and .spec.replicas >= ${2:-1}"
}

# _f2a_image_par_empreinte 'JSON du Deployment' — toutes les images medisphere/ du pod par @sha256:.
_f2a_image_par_empreinte() {
  _f2a_json "$1" '[.spec.template.spec.containers[].image | select(test("/medisphere/"))] as $i
    | ($i | length) > 0 and all($i[]; test("@sha256:[0-9a-f]{64}$"))'
}

# _f2a_empreinte 'JSON du Deployment' — empreinte (sha256:…) de l'image du service.
_f2a_empreinte() {
  jq -r --arg im "$_F2A_IMAGE" '[.spec.template.spec.containers[].image | select(contains($im))][0] // "" | capture("@(?<d>sha256:[0-9a-f]{64})$").d // ""' <<<"$1" 2>/dev/null || true
}

# --- HTTP ---------------------------------------------------------------------------------------------

# _f2a_url_200 URL — GET qui répond 200 (racine MédiSphère si présente).
_f2a_url_200() {
  local ca=()
  [[ -r "$_F2A_RACINE" ]] && ca=(--cacert "$_F2A_RACINE")
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "${ca[@]}" "$1" 2>/dev/null || true)" == 200 ]]
}

# --- Alertmanager -------------------------------------------------------------------------------------

# _f2a_am_config — configuration ACTIVE d'Alertmanager (texte YAML, configuration générée par l'opérateur).
_f2a_am_config() { am_api status 2>/dev/null | jq -r '.config.original // empty' 2>/dev/null || true; }

# _f2a_route_equipe EQUIPE 'CONFIG' — la configuration contient une route qui filtre equipe=EQUIPE et un
# récepteur qui écrit à EQUIPE@medisphere.internal.
_f2a_route_equipe() {
  grep -Eq "equipe *=~? *\"?${1}\"?|equipe: *${1}\b" <<<"$2" && grep -q "${1}@medisphere.internal" <<<"$2"
}
