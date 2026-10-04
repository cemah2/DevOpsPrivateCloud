#!/usr/bin/env bash
# conformite-plateforme.sh — met (ou vérifie) TOUS les projets du groupe plateforme en
# conformité avec les règles de l'équipe (M01-E47, PLAT-290).
#
# Usage :
#   forge/outils/conformite-plateforme.sh --verifier     compare, ne modifie rien ; code 1 si dérive
#   forge/outils/conformite-plateforme.sh --appliquer    applique (idempotent)
#
# Règles vérifiées pour chaque projet de plateforme/* (non archivé) :
#   - branche par défaut main ; main protégée : push « No one », fusion « Maintainers », pas de push forcé ;
#   - fusion seulement si le pipeline réussit et si les discussions sont résolues ;
#   - méthode de fusion de l'équipe (M01-E11 : rebase_merge = commit de fusion, historique semi-linéaire) ;
#   - étiquettes v* protégées, création réservée aux Maintainers ;
#   - fichiers .pre-commit-config.yaml et .gitlab-ci.yml présents sur main (vérifiés, pas créés).
# L'application des réglages de projet et de la protection de main est déléguée au script de
# M01-E11 (forge/outils/gitlab-proteger-projet.sh, même dossier) ; ce script-ci ajoute la
# protection des étiquettes et le mode comparaison.
#
# Jeton : WB_GITLAB_ADMIN_TOKEN_FILE (défaut ~/.config/workbook/gitlab-admin.token), portée api ;
# en mode --verifier, le jeton en lecture (WB_GITLAB_TOKEN_FILE) suffit.
set -euo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METHODE="${METHODE_FUSION:-rebase_merge}"

mode="${1:-}"
case "$mode" in
  --verifier) JETON_F="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}" ;;
  --appliquer) JETON_F="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}" ;;
  *) echo "Usage : $0 --verifier | --appliquer" >&2; exit 2 ;;
esac
for c in curl jq; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }; done
[[ -r "$JETON_F" ]] || { echo "jeton illisible : $JETON_F" >&2; exit 1; }

api() {   # api MÉTHODE CHEMIN [données curl…]
  local m="$1" p="$2"
  shift 2
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_F")") "$URL/api/v4/$p" "$@"
}
enc() { jq -rn --arg s "$1" '$s|@uri'; }

derives=0
ecart() { printf '  [ÉCART] %s\n' "$*"; derives=$((derives + 1)); }

controler() {   # controler PROJET — affiche les écarts, renvoie 0 si conforme
  local p="$1" e n=0 j
  e="projects/$(enc "$p")"
  j="$(api GET "$e")" || { ecart "$p : projet illisible"; return 1; }
  jq -e '.default_branch == "main"' >/dev/null <<<"$j" || { ecart "$p : branche par défaut différente de main"; n=1; }
  jq -e '.only_allow_merge_if_pipeline_succeeds' >/dev/null <<<"$j" || { ecart "$p : fusion possible sans pipeline réussi"; n=1; }
  jq -e '.only_allow_merge_if_all_discussions_are_resolved' >/dev/null <<<"$j" || { ecart "$p : discussions non résolues tolérées"; n=1; }
  jq -e --arg m "$METHODE" '.merge_method == $m' >/dev/null <<<"$j" || { ecart "$p : méthode de fusion $(jq -r .merge_method <<<"$j") au lieu de $METHODE"; n=1; }
  if j="$(api GET "$e/protected_branches/main")"; then
    jq -e '[.push_access_levels[].access_level] | length > 0 and all(. == 0)' >/dev/null <<<"$j" || { ecart "$p : poussée directe possible sur main"; n=1; }
    jq -e '[.merge_access_levels[].access_level] | length > 0 and all(. == 40)' >/dev/null <<<"$j" || { ecart "$p : fusion sur main pas réservée aux Maintainers"; n=1; }
    jq -e '.allow_force_push | not' >/dev/null <<<"$j" || { ecart "$p : poussée forcée autorisée sur main"; n=1; }
  else
    ecart "$p : main non protégée"; n=1
  fi
  if j="$(api GET "$e/protected_tags/$(enc 'v*')")"; then
    jq -e '[.create_access_levels[].access_level] | length > 0 and all(. == 40)' >/dev/null <<<"$j" || { ecart "$p : création des étiquettes v* pas réservée aux Maintainers"; n=1; }
  else
    ecart "$p : étiquettes v* non protégées"; n=1
  fi
  api GET "$e/repository/files/.pre-commit-config.yaml?ref=main" >/dev/null || { ecart "$p : pas de .pre-commit-config.yaml sur main"; n=1; }
  api GET "$e/repository/files/.gitlab-ci.yml?ref=main" >/dev/null || { ecart "$p : pas de .gitlab-ci.yml sur main"; n=1; }
  return "$n"
}

appliquer() {   # appliquer PROJET
  local p="$1" e opt=()
  e="projects/$(enc "$p")"
  [[ "$METHODE" == ff ]] && opt+=(--ff)
  WB_GITLAB_ADMIN_TOKEN_FILE="$JETON_F" "$ICI/gitlab-proteger-projet.sh" "$p" --pipeline-obligatoire "${opt[@]}"
  if ! api GET "$e/protected_tags/$(enc 'v*')" \
       | jq -e '[.create_access_levels[].access_level] | length > 0 and all(. == 40)' >/dev/null 2>&1; then
    # Pas de modification possible d'une protection d'étiquette par l'API : on la recrée.
    api DELETE "$e/protected_tags/$(enc 'v*')" >/dev/null 2>&1 || true
    api POST "$e/protected_tags" --data-urlencode 'name=v*' -d create_access_level=40 >/dev/null
  fi
}

projets="$(api GET 'groups/plateforme/projects?per_page=100&include_subgroups=true&archived=false' \
  | jq -r '.[].path_with_namespace' | sort)"
[[ -n "$projets" ]] || { echo "aucun projet dans le groupe plateforme" >&2; exit 1; }

while IFS= read -r p; do
  echo "== $p"
  if controler "$p"; then
    echo "  conforme"
  elif [[ "$mode" == --appliquer ]]; then
    appliquer "$p"
    derives_avant=$derives
    if controler "$p"; then echo "  mis en conformité"; else echo "  ÉCARTS RESTANTS (fichiers à ajouter par MR ?)"; fi
    derives=$derives_avant
  fi
done <<<"$projets"

if [[ "$mode" == --verifier && $derives -gt 0 ]]; then
  echo "$derives écart(s) détecté(s)."
  exit 1
fi
echo "Terminé."
