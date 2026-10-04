# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M01-E07 : historique de formation/git-labo, étiquette e07/seuil, intégrations.
# Lancé depuis adm01. Lecture seule : API GitLab avec le jeton des checks.

title "M01-E07 — Lire et construire un historique"
require_cmd curl jq

_m01_api="projects/formation%2Fgit-labo"

_m01_jq() {
  local desc="$1" filtre="$2" json="$3"; shift 3
  check_cmd "$desc" jq -e "$@" "$filtre" <<<"${json:-null}"
}
# Encodage d'un nom de branche ou d'étiquette pour l'URL de l'API (le « / » devient %2F)
_m01_ref() { printf '%s' "${1//\//%2F}"; }
_m01_branche() { gitlab_api "$_m01_api/repository/branches/$(_m01_ref "$1")" 2>/dev/null || true; }

# --- Publication du dépôt d'exercice ------------------------------------------------------------
_m01_jq "projet formation/git-labo présent et privé" '.visibility == "private"' \
  "$(gitlab_api "$_m01_api" 2>/dev/null || true)"
for _m01_b in main correctif/espaces-noms fonction/export-csv fonction/sortie-json fonction/tri infoger/ancien-format; do
  _m01_jq "branche $_m01_b publiée" '.name == $b' "$(_m01_branche "$_m01_b")" --arg b "$_m01_b"
done
for _m01_t in v0.1.0 v0.2.0 livraison-infoger; do
  _m01_jq "étiquette $_m01_t publiée" '.name == $t' \
    "$(gitlab_api "$_m01_api/repository/tags/$_m01_t" 2>/dev/null || true)" --arg t "$_m01_t"
done
_m01_jq "v0.2.0 désigne le commit de fusion de fonction/export-csv" \
  '.commit.title == "Merge branch '"'"'fonction/export-csv'"'"'" and (.commit.parent_ids | length) == 2' \
  "$(gitlab_api "$_m01_api/repository/tags/v0.2.0" 2>/dev/null || true)"

# --- Étiquette e07/seuil -----------------------------------------------------------------------
_m01_seuil="$(gitlab_api "$_m01_api/repository/tags/$(_m01_ref e07/seuil)" 2>/dev/null || true)"
_m01_jq "étiquette e07/seuil publiée" '.name == "e07/seuil"' "$_m01_seuil"
_m01_jq "e07/seuil est une étiquette légère" '.commit.id != null and .target == .commit.id' "$_m01_seuil"
_m01_jq "e07/seuil désigne le commit qui a introduit SEUIL_ALERTE" \
  '.commit.title == "Corrections diverses" and .commit.author_name == "InfoGér Support"' "$_m01_seuil"

# --- Intégrations ----------------------------------------------------------------------------
_m01_pbs="$(_m01_branche e07/ajout-pbs)"
_m01_dns="$(_m01_branche e07/ajout-dns)"
_m01_int="$(_m01_branche e07/integration)"
_m01_jq "e07/ajout-pbs : un commit ordinaire (un seul parent)" '(.commit.parent_ids | length) == 1' "$_m01_pbs"
_m01_jq "e07/ajout-dns : un commit ordinaire (un seul parent)" '(.commit.parent_ids | length) == 1' "$_m01_dns"
_m01_jq "e07/ajout-pbs et e07/ajout-dns partent du même commit" \
  '.[0].commit != null and .[1].commit != null and .[0].commit.parent_ids[0] == .[1].commit.parent_ids[0]' "[${_m01_pbs:-null},${_m01_dns:-null}]"
for _m01_b in e07/ajout-pbs e07/ajout-dns; do
  _m01_jq "$_m01_b : exactement un commit absent de main" '(.commits | length) == 1' \
    "$(gitlab_api "$_m01_api/repository/compare?from=main&to=$(_m01_ref "$_m01_b")" 2>/dev/null || true)"
done
_m01_jq "e07/integration se termine par un commit de fusion (deux parents)" \
  '(.commit.parent_ids | length) == 2' "$_m01_int"
_m01_jq "commit de fusion : message par défaut pour e07/ajout-dns" \
  '.commit.title | startswith("Merge branch '"'"'e07/ajout-dns'"'"'")' "$_m01_int"
_m01_jq "premier parent de la fusion = e07/ajout-pbs (intégrée par avance rapide)" \
  '.[1].commit.id != null and .[0].commit.parent_ids[0] == .[1].commit.id' "[${_m01_int:-null},${_m01_pbs:-null}]"
_m01_jq "second parent de la fusion = e07/ajout-dns" \
  '.[1].commit.id != null and .[0].commit.parent_ids[1] == .[1].commit.id' "[${_m01_int:-null},${_m01_dns:-null}]"
