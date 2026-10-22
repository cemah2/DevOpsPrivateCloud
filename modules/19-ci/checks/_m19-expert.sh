# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
# _m19-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 19
# (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule : API GitLab en GET
# (gitlab_api, jeton read_api des checks), API Harbor en GET (robot des checks), kubectl en lecture avec
# le compte wb-checks (fonction « kube » ; ClusterRole agrégée wb-checks-livraison, jamais les Secrets).
# Préfixe _m19x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m19x_temoin="${WB_M19_TEMOIN:-formation/ci-pannes}"
_m19x_runner="${WB_M19_RUNNER:-k8s-par1}"
_m19x_depot="${WB_DEPOT:-$HOME/medisphere}"
_m19x_ns_runner=gitlab-runner

# _m19x_enc CHAÎNE — encodage URL.
_m19x_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _m19x_gl 'filtre jq' CHEMIN — 0 si la réponse GET de l'API GitLab satisfait le filtre.
_m19x_gl() { gitlab_api "$2" 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }

# _m19x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m19x_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

_m19x_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _m19x_brut PROJET CHEMIN [REF] — contenu brut d'un fichier d'un dépôt GitLab.
_m19x_brut() {
  gitlab_api "projects/$(_m19x_enc "$1")/repository/files/$(_m19x_enc "$2")/raw?ref=$(_m19x_enc "${3:-main}")" 2>/dev/null
}

_m19x_temoin_existe() { gitlab_api "projects/$(_m19x_enc "$_m19x_temoin")" >/dev/null 2>&1; }

# _m19x_runner_json [NOM] — détail du runner d'instance dont la description est NOM.
_m19x_runner_json() {
  local id
  id="$(gitlab_api "runners/all?type=instance_type&per_page=100" 2>/dev/null |
    jq -r --arg n "${1:-$_m19x_runner}" '[.[] | select(.description == $n)][0].id // empty')"
  [[ -n "$id" ]] || return 1
  gitlab_api "runners/$id"
}

# _m19x_dernier_pipeline PROJET [REF] — JSON du dernier pipeline terminé ou en cours de la référence.
_m19x_dernier_pipeline() {
  gitlab_api "projects/$(_m19x_enc "$1")/pipelines?ref=$(_m19x_enc "${2:-main}")&per_page=1&order_by=id&sort=desc" 2>/dev/null |
    jq -c '.[0] // empty'
}

# _m19x_pipeline_vert PROJET [REF] — le dernier pipeline de la référence a réussi.
_m19x_pipeline_vert() { _m19x_dernier_pipeline "$1" "${2:-main}" | jq -e '.status == "success"' >/dev/null 2>&1; }

# _m19x_canari_job — identifiant du job canari du dernier pipeline réussi de main du témoin.
_m19x_canari_job() {
  local pl
  pl="$(gitlab_api "projects/$(_m19x_enc "$_m19x_temoin")/pipelines?ref=main&status=success&per_page=1&order_by=id&sort=desc" 2>/dev/null |
    jq -r '.[0].id // empty')"
  [[ -n "$pl" ]] || return 1
  gitlab_api "projects/$(_m19x_enc "$_m19x_temoin")/pipelines/$pl/jobs?per_page=100" 2>/dev/null |
    jq -r '[.[] | select(.name == "canari" and .status == "success")][0].id // empty'
}

# _m19x_canari_vert — le dernier pipeline de main du témoin a réussi (job canari compris).
_m19x_canari_vert() { _m19x_pipeline_vert "$_m19x_temoin" main && [[ -n "$(_m19x_canari_job)" ]]; }

# _m19x_canari_trace 'regex' — le journal du dernier job canari réussi correspond.
_m19x_canari_trace() {
  local j
  j="$(_m19x_canari_job)" || return 1
  [[ -n "$j" ]] || return 1
  gitlab_api "projects/$(_m19x_enc "$_m19x_temoin")/jobs/$j/trace" 2>/dev/null | grep -Eq -- "$1"
}

# _m19x_canari_version — version du composant canari consommée sur main du témoin.
_m19x_canari_version() {
  _m19x_brut "$_m19x_temoin" .gitlab-ci.yml main | sed -n 's|.*/canari@\([0-9][0-9.]*\).*|\1|p' | head -n 1
}

# _m19x_canari_gabarit — gabarit du composant canari à la version consommée.
_m19x_canari_gabarit() {
  local v
  v="$(_m19x_canari_version)"
  [[ -n "$v" ]] || return 1
  _m19x_brut "$_m19x_temoin" templates/canari/template.yml "$v"
}

# _m19x_toml — gabarit TOML du runner k8s-par1 (ConfigMap du chart dont les jobs vont dans ci-jobs).
_m19x_toml() {
  kube -n "$_m19x_ns_runner" get configmaps -o json 2>/dev/null | jq -r '
    [.items[] | .data["config.template.toml"] // empty | select(test("namespace *= *\"ci-jobs\""))][0] // empty'
}

# _m19x_toml_valeur CLÉ — valeur (sans guillemets) d'une clé du gabarit, vide si absente.
_m19x_toml_valeur() {
  _m19x_toml | sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\\1/p" | head -n 1
}

# _m19x_mio QUANTITÉ — quantité Kubernetes en Mio (entier), 0 si illisible.
_m19x_mio() {
  local q="$1"
  case "$q" in
    *Ki) echo $((${q%Ki} / 1024)) ;;
    *Mi) echo "${q%Mi}" ;;
    *Gi) echo $((${q%Gi} * 1024)) ;;
    *M) echo $((${q%M} * 1000000 / 1048576)) ;;
    *G) echo $((${q%G} * 1000000000 / 1048576)) ;;
    '' | *[!0-9]*) echo 0 ;;
    *) echo $((q / 1048576)) ;;
  esac
}

# _m19x_runner_deploy_pret — le Deployment du gestionnaire de k8s-par1 est entièrement disponible.
_m19x_runner_deploy_pret() {
  local cm
  cm="$(kube -n "$_m19x_ns_runner" get configmaps -o json 2>/dev/null | jq -r '
    [.items[] | select(.data["config.template.toml"] // "" | test("namespace *= *\"ci-jobs\""))][0].metadata.name // empty')"
  [[ -n "$cm" ]] || return 1
  kube -n "$_m19x_ns_runner" get deploy -o json 2>/dev/null | jq -e --arg cm "$cm" '
    [.items[] | select(any(.spec.template.spec.volumes[]?; .configMap.name? == $cm))][0]
    | (.spec.replicas // 1) as $n | $n >= 1 and (.status.availableReplicas // 0) == $n and (.status.updatedReplicas // 0) == $n' >/dev/null 2>&1
}

# _m19x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M19-* si aucune) n'est marquée.
_m19x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M19-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M19-$e" ]] || return 1
  done
}

# _m19x_doc MOTIF — premier fichier du dépôt de documentation dont le nom correspond (sous docs/) ;
# un runbook (MOTIF « RB-… ») n'est cherché qu'à son emplacement unique, docs/livraison/ci/runbooks/.
_m19x_doc() {
  local d=docs
  [[ "$1" == RB-* ]] && d=docs/livraison/ci/runbooks
  (cd "$_m19x_depot" 2>/dev/null && find "$d" -type f -name "$1" 2>/dev/null | sort | head -n 1)
}

# _m19x_doc_contient MOTIF 'regex' — ce fichier existe et contient la regex (insensible à la casse).
_m19x_doc_contient() {
  local f
  f="$(_m19x_doc "$1")"
  [[ -n "$f" ]] && grep -Eqi -- "$2" "$_m19x_depot/$f"
}

# _m19x_doc_commite MOTIF — ce fichier est suivi par git et sans modification en attente.
_m19x_doc_commite() {
  local f
  f="$(_m19x_doc "$1")"
  [[ -n "$f" ]] || return 1
  (cd "$_m19x_depot" && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "$f")" ]])
}

# _m19x_sans_secret MOTIF — le fichier ne contient ni jeton GitLab, ni clé privée, ni JWT.
_m19x_sans_secret() {
  local f
  f="$(_m19x_doc "$1")"
  [[ -n "$f" ]] && ! grep -Eq 'glrt-[A-Za-z0-9_-]{8}|glpat-[A-Za-z0-9_-]{8}|glagent-[A-Za-z0-9_-]{8}|glcbt-[A-Za-z0-9_-]{8}|PRIVATE KEY|eyJhbGciOi' "$_m19x_depot/$f"
}
