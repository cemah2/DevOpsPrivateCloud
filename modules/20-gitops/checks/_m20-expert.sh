# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# _m20-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 20
# (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule : kubectl en
# lecture avec le compte des checks (« kube » : ClusterRoles agrégées wb-checks-*, jamais les
# Secrets), API GitLab en GET (jeton read_api), API d'Argo CD en GET (jeton du compte local
# ci-lecture, M20-E03), commandes de consultation sur lyo-k3s01 et les passerelles (sudo -n).
# Préfixe _m20x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m20x_ns=argocd
_m20x_depot="${WB_DEPOT:-$HOME/medisphere}"
_m20x_app_dev="${WB_M20_APP_DEV:-mediagenda-dev}"
_m20x_app_recette="${WB_M20_APP_RECETTE:-mediagenda-recette}"
_m20x_app_prod="${WB_M20_APP_PROD:-mediagenda-prod}"
_m20x_app_labo="${WB_M20_APP_LABO:-labo}"
_m20x_ns_dev="${WB_M20_NS_DEV:-mediagenda-dev}"
_m20x_ns_recette="${WB_M20_NS_RECETTE:-mediagenda-recette}"
_m20x_ns_prod="${WB_M20_NS_PROD:-mediagenda-prod}"
_m20x_lyo="${WB_M20_LYO_HOTE:-10.10.99.61}"
_m20x_argocd_url="${WB_ARGOCD_URL:-https://argocd.apps.par1.medisphere.internal}"
# RB-200 (M20-E22) : à la racine de docs/livraison/gitops/ ou dans son sous-dossier runbooks/.
_m20x_rb200="docs/livraison/gitops/RB-200*.md docs/livraison/gitops/runbooks/RB-200*.md"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _m20x_gitops=plateforme/gitops
  _m20x_deploiement=mediagenda/deploiement
}

# _m20x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m20x_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m20x_argo_lisible — le compte des checks lit les Applications d'Argo CD (garde-fou commun).
_m20x_argo_lisible() { kube -n "$_m20x_ns" get applications.argoproj.io >/dev/null 2>&1; }

_m20x_app() { kube -n "$_m20x_ns" get applications.argoproj.io "$1" -o json 2>/dev/null; }
_m20x_app_existe() { kube -n "$_m20x_ns" get applications.argoproj.io "$1" >/dev/null 2>&1; }

# _m20x_app_jq APP 'filtre' — 0 si l'Application satisfait le filtre.
_m20x_app_jq() { _m20x_app "$1" | jq -e "$2" >/dev/null 2>&1; }

# _m20x_app_saine APP — Synced, Healthy, sans erreur de comparaison ni opération en échec.
_m20x_app_saine() {
  _m20x_app_jq "$1" '.status.sync.status == "Synced" and .status.health.status == "Healthy"
    and ([.status.conditions[]? | select(.type | test("Error$"))] | length == 0)
    and ((.status.operationState.phase // "Succeeded") == "Succeeded")'
}

# _m20x_apps_sans 'regex de type de condition' — aucune Application ne porte une telle condition.
_m20x_apps_sans() {
  kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null |
    jq -e --arg r "$1" '[.items[] | .status.conditions[]? | select(.type | test($r))] | length == 0' >/dev/null 2>&1
}

# _m20x_apps_de_appset NOM — Applications créées par l'ApplicationSet NOM (référence propriétaire).
_m20x_apps_de_appset() {
  kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg n "$1" '.items[] | select(any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == $n)) | .metadata.name'
}

# _m20x_cm ESPACE NOM — ConfigMap en JSON.
_m20x_cm() { kube -n "$1" get configmap "$2" -o json 2>/dev/null; }

# _m20x_argocd_api CHEMIN — GET sur l'API d'Argo CD avec le jeton de ci-lecture (M20-E03).
_m20x_argocd_api() {
  local f="${WB_ARGOCD_TOKEN_FILE:-$HOME/.config/workbook/argocd-checks.token}"
  [[ -r "$f" ]] || return 1
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '[:space:]' <"$f")") \
    -H "Accept: application/json" "$_m20x_argocd_url/api/v1/$1"
}

# _m20x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M20-* si aucune) n'est marquée.
_m20x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M20-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M20-$e" ]] || return 1
  done
}

# _m20x_doc_commite 'MOTIF [MOTIF…]' — un fichier du dépôt de documentation correspond à l'un des
# motifs (séparés par des espaces), suivi par git et sans modification en attente.
_m20x_doc_commite() {
  (
    cd "$_m20x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206  # motif de chemin voulu
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    git ls-files --error-unmatch "${f[0]}" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "${f[0]}")" ]]
  )
}

# _m20x_doc_contient 'MOTIF [MOTIF…]' 'regex' — un des fichiers correspondant contient la regex.
_m20x_doc_contient() {
  (
    cd "$_m20x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    grep -Eqi -- "$2" "${f[@]}"
  )
}

# _m20x_journal TICKET — une entrée du journal de diagnostic (docs/kubernetes/journal/) cite le
# ticket et elle est commitée.
_m20x_journal() {
  (
    cd "$_m20x_depot/docs/kubernetes/journal" 2>/dev/null || exit 1
    local f
    f="$(grep -lE -- "$1" ./*.md 2>/dev/null | head -n 1)"
    [[ -n "$f" ]] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "$f")" ]]
  )
}

# _m20x_gitlab_brut PROJET CHEMIN — contenu d'un fichier sur main (jeton read_api des checks).
_m20x_gitlab_brut() {
  gitlab_api "projects/$(jq -rn --arg s "$1" '$s|@uri')/repository/files/$(jq -rn --arg s "$2" '$s|@uri')/raw?ref=main"
}

# _m20x_gitlab_dossier PROJET DOSSIER — contenu concaténé des fichiers YAML et .env du dossier (main).
_m20x_gitlab_dossier() {
  local p f
  p="$(jq -rn --arg s "$1" '$s|@uri')"
  gitlab_api "projects/$p/repository/tree?ref=main&path=$(jq -rn --arg s "$2" '$s|@uri')&recursive=true&per_page=100" 2>/dev/null |
    jq -r '.[] | select(.type == "blob") | .path | select(test("\\.(ya?ml|env)$"))' 2>/dev/null |
    while read -r f; do _m20x_gitlab_brut "$1" "$f" 2>/dev/null; printf '\n'; done
}

# _m20x_mr_lucas_ouvertes PROJET — nombre de MR ouvertes depuis une branche lucas/… (pannes non closes).
_m20x_mr_lucas_ouvertes() {
  gitlab_api "projects/$(jq -rn --arg s "$1" '$s|@uri')/merge_requests?state=opened&per_page=100" 2>/dev/null |
    jq '[.[] | select(.source_branch | startswith("lucas/") or startswith("wb/annulation-"))] | length' 2>/dev/null || echo 0
}

# _m20x_deploy_pret ESPACE NOM — déploiement entièrement à jour et disponible.
_m20x_deploy_pret() {
  _m20x_kq '(.spec.replicas // 1) as $n | (.status.updatedReplicas // 0) == $n and (.status.availableReplicas // 0) == $n
            and (.status.observedGeneration // 0) >= .metadata.generation' -n "$1" deploy "$2"
}

# _m20x_rollout_sain ESPACE NOM — Rollout Healthy, ni en pause ni interrompu.
_m20x_rollout_sain() {
  _m20x_kq '.status.phase == "Healthy" and ((.spec.paused // false) == false) and ((.status.abort // false) == false)
            and ((.status.pauseConditions // []) | length == 0)' -n "$1" rollouts.argoproj.io "$2"
}

# _m20x_cnpg_proteges ESPACE… — chaque base CNPG de ces espaces porte Prune=false (élagage impossible).
_m20x_cnpg_proteges() {
  local ns
  for ns in "$@"; do
    kube -n "$ns" get clusters.postgresql.cnpg.io -o json 2>/dev/null | jq -e '
      all(.items[]; (.metadata.annotations["argocd.argoproj.io/sync-options"] // "") | test("(^|,)\\s*Prune=false\\s*(,|$)"))' >/dev/null 2>&1 || return 1
  done
}

# _m20x_gestionnaires_etrangers ESPACE KIND NOM — gestionnaires de champs (hors sous-ressource
# status) qui ne sont ni Argo CD ni les contrôleurs du cluster ou d'Argo Rollouts.
_m20x_gestionnaires_etrangers() {
  kube -n "$1" get "$2" "$3" -o json 2>/dev/null | jq -r '
    [.metadata.managedFields[]? | select((.subresource // "") == "")
     | .manager | select(test("^(argocd|kube-controller-manager|rollouts-controller|argo-rollouts)") | not)] | unique | join(",")'
}

# _m20x_noeud_lyo 'commande' — commande de lecture en root sur lyo-k3s01 ; code de retour.
_m20x_noeud_lyo() { remote "$_m20x_lyo" "sudo -n bash -c $(printf '%q' "$1")" </dev/null >/dev/null 2>&1; }
_m20x_noeud_lyo_sortie() { remote "$_m20x_lyo" "sudo -n bash -c $(printf '%q' "$1")" </dev/null 2>/dev/null; }

# _m20x_vm_absente VMID — la VM n'existe plus sur pve01.
_m20x_vm_absente() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
    jq -e --argjson v "$1" '[.[] | select(.vmid == $v)] | length == 0' >/dev/null 2>&1
}
_m20x_vm_presente() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
    jq -e --argjson v "$1" '[.[] | select(.vmid == $v)] | length == 1' >/dev/null 2>&1
}

# _m20x_fichier_present PROJET NOM_DE_FICHIER — un fichier de ce nom existe sur main du projet
# (n'importe où dans l'arbre : chaque équipe range ses outils à sa façon).
_m20x_fichier_present() {
  local p page=1 r
  p="$(jq -rn --arg s "$1" '$s|@uri')"
  while ((page <= 20)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page" 2>/dev/null)" || return 1
    jq -e --arg n "$2" '[.[] | select(.type == "blob" and (.path | split("/") | last) == $n)] | length > 0' >/dev/null 2>&1 <<<"$r" && return 0
    (($(jq 'length' <<<"$r") < 100)) && return 1
    page=$((page + 1))
  done
  return 1
}
