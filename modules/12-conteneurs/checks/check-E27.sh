# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E27.sh — M12-E27 « Politique des images de base de MédiSphère »
# Lecture seule : API GitLab (fichiers, pipelines planifiés, pipelines), API du registre de travail
# (étiquettes, configuration d'image).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E27 — Images de base"
require_cmd jq curl

title "Projet plateforme/images-base"
check_cmd "le projet existe" gitlab_api "projects/plateforme%2Fimages-base"
_m12_e27_arbre="$(gitlab_api "projects/plateforme%2Fimages-base/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null || echo '[]')"
_m12_e27_df="$(jq -r '.[]? | select(.type == "blob" and (.name | test("^(Dockerfile|Containerfile)"))) | .path' <<<"$_m12_e27_arbre" 2>/dev/null || true)"
check_cmd "au moins trois Dockerfiles d'images bibliotheque/" test "$(grep -c . <<<"$_m12_e27_df")" -ge 3
_m12_e27_epingle=0
[[ -n "$_m12_e27_df" ]] && _m12_e27_epingle=1
while read -r _m12_e27_f; do
  [[ -n "$_m12_e27_f" ]] || continue
  _m12_e27_c="$(_m12p_fichier_main plateforme/images-base "$_m12_e27_f" 2>/dev/null || true)"
  # Chaque image amont (dans un FROM ou un ARG utilisé par FROM) est référencée par empreinte.
  grep -Eq '@sha256:[0-9a-f]{64}' <<<"$_m12_e27_c" || _m12_e27_epingle=0
  grep -Eiq '^FROM[[:space:]]+([^$@[:space:]]+:[^@[:space:]]+|[^$@:[:space:]]+)([[:space:]]|$)' <<<"$_m12_e27_c" && _m12_e27_epingle=0
done <<<"$_m12_e27_df"
check_output "les Dockerfiles ne référencent l'amont que par empreinte" '^1$' echo "$_m12_e27_epingle"
check_cmd "liste des images autorisées sur main" \
  bash -c 'jq -e "any(.[]?; .type == \"blob\" and (.name | test(\"autoris\")))" >/dev/null <<<"$1"' _ "$_m12_e27_arbre"

title "Reconstruction hebdomadaire"
_m12_e27_plan="$(gitlab_api "projects/plateforme%2Fimages-base/pipeline_schedules" 2>/dev/null || echo '[]')"
check_cmd "un pipeline planifié hebdomadaire actif" bash -c \
  'jq -e "any(.[]?; .active == true and (.cron | split(\" \") | .[4] | test(\"^[0-6]$|^(mon|tue|wed|thu|fri|sat|sun)$\"; \"i\")))" >/dev/null <<<"$1"' _ "$_m12_e27_plan"
_m12_e27_recent="$(gitlab_api "projects/plateforme%2Fimages-base/pipelines?source=schedule&per_page=1" 2>/dev/null || echo '[]')"
_m12_e27_planifie_ok() {
  local statut cree
  statut="$(jq -r '.[0].status // empty' <<<"$_m12_e27_recent" 2>/dev/null)"
  cree="$(jq -r '.[0].created_at // empty' <<<"$_m12_e27_recent" 2>/dev/null)"
  [[ "$statut" == success && -n "$cree" ]] || return 1
  (($(date -d "$cree" +%s) > $(date +%s) - 8 * 86400))
}
check_cmd "dernière exécution planifiée réussie, de moins de 8 jours" _m12_e27_planifie_ok

title "Registre de travail"
_m12_e27_tags="$(_m12p_etiquettes bibliotheque/debian || true)"
_m12_e27_date="$(grep -E -- '-[0-9]{8}$' <<<"$_m12_e27_tags" | sed -E 's/.*-([0-9]{8})$/\1/' | sort | tail -n 1 || true)"
check_cmd "bibliotheque/debian : étiquette datée de moins de 8 jours" \
  bash -c '[[ "$1" =~ ^[0-9]{8}$ ]] && (( $(date -d "$1" +%s) > $(date +%s) - 8 * 86400 ))' _ "$_m12_e27_date"
check_cmd "bibliotheque/debian : une étiquette mobile (sans date)" \
  bash -c '[[ -n "$1" ]] && grep -Evq -- "-[0-9]{8}$|^latest$" <<<"$1"' _ "$_m12_e27_tags"
check_cmd "bibliotheque/debian : pas d'étiquette latest" bash -c '[[ -n "$1" ]] && ! grep -qx latest <<<"$1"' _ "$_m12_e27_tags"
_m12_e27_tagdate="$(grep -E -- "-${_m12_e27_date:-X}$" <<<"$_m12_e27_tags" | head -n 1 || true)"
_m12_e27_cfg="$(_m12p_config bibliotheque/debian "${_m12_e27_tagdate:-absente}" || echo null)"
check_cmd "l'image porte les étiquettes OCI de provenance (base.name avec empreinte, revision)" _m12p_jq "$_m12_e27_cfg" \
  '(.config.Labels // {}) | (."org.opencontainers.image.base.name" // "" | test("@sha256:")) and ((."org.opencontainers.image.revision" // "") | length > 6)'

title "Contrôle des images autorisées"
check_cmd "plateforme/ci-templates : gabarit images-autorisees sur main" \
  _m12p_arbre_contient plateforme/ci-templates 'autoris.*\.ya?ml$'
check_cmd "mediagenda/api : le pipeline inclut le contrôle" \
  _m12p_doc_main mediagenda/api .gitlab-ci.yml 'images-autorisees|images_autorisees'
check_cmd "docs/conteneurs/images-de-base.md sur main" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/images-de-base.md 'bibliotheque' 'empreinte|sha256'
