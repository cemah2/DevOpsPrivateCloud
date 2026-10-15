# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _m13-operationnel.sh — fonctions partagées par les checks M13-E06 à M13-E12 (lecture seule).
# Réutilise _m13-decouverte.sh (Harbor, GitLab, cosign avec wb-checks). Préfixe _m13o_.

# shellcheck source=_m13-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-decouverte.sh"

_M13O_APPS=(mediagenda-api medidoc medinotif legacy-rdv)
_M13O_GROUPES=(mediagenda medidoc medinotif legacy)

# _m13o_ref_version DÉPÔT — référence par empreinte de la dernière version de medisphere/DÉPÔT
#   (registry…/medisphere/DÉPÔT@sha256:…), vide si aucune.
_m13o_ref_version() {
  local t d
  t="$(_m13d_derniere_version medisphere "$1")"
  [[ -n "$t" ]] || return 0
  d="$(_m13d_empreinte medisphere "$1" "$t")"
  [[ -n "$d" ]] && printf '%s/medisphere/%s@%s' "$_M13D_NOM" "$1" "$d"
  return 0
}

# _m13o_var_groupe GROUPE CLÉ — objet JSON de la variable de CI du groupe (vide si absente).
_m13o_var_groupe() { gitlab_api "groups/$1/variables/$2" 2>/dev/null || true; }

# _m13o_var_projet PROJET_ENCODÉ CLÉ — idem pour un projet (ex. plateforme%2Frenovate).
_m13o_var_projet() { gitlab_api "projects/$1/variables/$2" 2>/dev/null || true; }

# _m13o_doc CHEMIN — le fichier existe sur main de plateforme/medisphere.
_m13o_doc() { _m13d_fichier_main "$_M13D_DOC" "$1"; }
