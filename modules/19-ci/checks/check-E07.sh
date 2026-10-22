# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M19-E07 : variables, artefacts, caches et environnements
# À lancer depuis adm01. Lecture seule : requêtes S3 signées en GET sur s3-01 (identité ci-cache, fichier
# WB_S3_CI_CACHE_FILE), ConfigMap du gestionnaire (wb-checks), API GitLab en GET (journaux de jobs,
# environnements, déploiements).

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E07 — Variables, artefacts, caches et environnements"
require_cmd jq curl kubectl

_m19d_e07_pid="$(_m19d_api "projects/$(_m19d_enc "$_M19D_LABO")" | jq -r '.id // empty' 2>/dev/null || true)"

# --- 1. L'identité ci-cache de s3-01 -----------------------------------------------------------------
check_cmd "$_M19D_S3_ENV en 600" _m19d_local600 "$_M19D_S3_ENV"
if [[ -r "$_M19D_S3_ENV" ]]; then
  _m19d_e07_liste="$(_m19d_s3_get 'ci-cache?list-type=2&max-keys=1000')"
  check_output "l'identité ci-cache liste le compartiment ci-cache (HTTP 200)" '^200$' \
    bash -c 'tail -n 1 <<<"$1"' _ "$_m19d_e07_liste"
  check_output "l'identité ci-cache ne lit pas un autre compartiment (tofu-state : 403)" '^403$' \
    bash -c 'tail -n 1 <<<"$1"' _ "$(_m19d_s3_get 'tofu-state?list-type=2&max-keys=1')"
  if [[ -n "$_m19d_e07_pid" ]]; then
    check_cmd "ci-cache contient des caches de $_M19D_LABO (…/project/$_m19d_e07_pid/…)" bash -c \
      'grep -oE "<Key>[^<]*</Key>" <<<"$1" | grep -q "/project/$2/"' _ "$_m19d_e07_liste" "$_m19d_e07_pid"
  else
    skip "objets de cache de $_M19D_LABO" "projet introuvable"
  fi
else
  skip "accès S3 avec l'identité ci-cache" "$_M19D_S3_ENV illisible"
fi

# --- 2. La configuration du runner (ConfigMap, jamais le Secret) ---------------------------------------
_m19d_e07_toml="$(_m19d_kj -n gitlab-runner get configmap gitlab-runner | jq -r '.data["config.template.toml"] // ""' 2>/dev/null || true)"
check_output "runner : cache de type s3" '^\s*Type\s*=\s*"s3"' printf '%s\n' "$_m19d_e07_toml"
check_output "runner : cache sur s3-01:8333" '^\s*ServerAddress\s*=\s*"s3-01\.par1\.medisphere\.internal:8333"' printf '%s\n' "$_m19d_e07_toml"
check_output "runner : compartiment ci-cache" '^\s*BucketName\s*=\s*"ci-cache"' printf '%s\n' "$_m19d_e07_toml"
check_cmd "runner : aucune clé S3 écrite dans la configuration (AccessKey, SecretKey)" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "^\s*(AccessKey|SecretKey)\s*=" <<<"$1"' _ "$_m19d_e07_toml"
check_cmd "runner : clés du cache par le Secret ci-cache-s3 (volume du Deployment, contenu non lu)" _m19d_json \
  "$(_m19d_kj -n gitlab-runner get deployment gitlab-runner)" \
  'any(.spec.template.spec.volumes[]?; any(.projected.sources[]?; (.secret.name // "") == "ci-cache-s3"))'

# --- 3. Un cache réellement réutilisé (journaux des jobs récents) --------------------------------------
_m19d_e07_reutilise() {
  local pipelines pid jid n=0
  pipelines="$(_m19d_pipelines "$_M19D_LABO" 'per_page=8' | jq -r '.[]?.id' 2>/dev/null || true)"
  for pid in $pipelines; do
    for jid in $(_m19d_jobs "$_M19D_LABO" "$pid" | jq -r '.[]? | select(.status == "success") | .id' 2>/dev/null || true); do
      n=$((n + 1))
      ((n <= 30)) || return 1
      # Clé calculée à partir d'un fichier : une empreinte de 40 caractères hexadécimaux dans la clé.
      if _m19d_trace "$_M19D_LABO" "$jid" | grep -E 'Checking cache for [^ ]*[0-9a-f]{40}' -A 6 \
        | grep -q 'Successfully extracted cache'; then
        return 0
      fi
    done
  done
  return 1
}
check_cmd "un job récent de $_M19D_LABO a réutilisé un cache dont la clé vient d'un fichier (key:files)" _m19d_e07_reutilise

# --- 4. Environnements et déploiements -------------------------------------------------------------------
if [[ -n "$_m19d_e07_pid" ]]; then
  _m19d_e07_env="$(_m19d_api "projects/$_m19d_e07_pid/environments?per_page=50")"
  for _m19d_e07_e in "dev development" "recette staging" "prod production"; do
    read -r _m19d_e07_nom _m19d_e07_tier <<<"$_m19d_e07_e"
    check_cmd "environnement $_m19d_e07_nom : tier $_m19d_e07_tier, URL déclarée" _m19d_json "$_m19d_e07_env" \
      'any(.[]; .name == $n and .tier == $t and ((.external_url // "") != ""))' --arg n "$_m19d_e07_nom" --arg t "$_m19d_e07_tier"
  done
  check_cmd "environnement dev : au moins un déploiement réussi" _m19d_json \
    "$(_m19d_api "projects/$_m19d_e07_pid/deployments?environment=dev&status=success&per_page=1")" 'length >= 1'
  check_cmd ".gitlab-ci.yml de main : resource_group et cache par fichier (key:files)" bash -c \
    'grep -Eq "^\s*resource_group:" <<<"$1" && grep -Eq "^\s*files:" <<<"$1"' _ "$(_m19d_contenu_main "$_M19D_LABO" .gitlab-ci.yml)"
else
  skip "environnements de $_M19D_LABO" "projet introuvable"
fi
