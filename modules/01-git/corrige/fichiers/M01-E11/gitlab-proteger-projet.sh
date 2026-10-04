#!/usr/bin/env bash
# gitlab-proteger-projet.sh — applique les règles de l'équipe Plateforme à un projet GitLab.
#
# Usage : gitlab-proteger-projet.sh GROUPE/PROJET [--ff] [--pipeline-obligatoire] [--dry-run]
#   --ff                    méthode de fusion fast-forward au lieu du commit de fusion semi-linéaire
#   --pipeline-obligatoire  fusion seulement si le pipeline réussit (à partir de M01-E24)
#   --dry-run               affiche les appels sans rien modifier
#
# Règles (M01-E11) :
#   - main protégée : push « No one », fusion « Maintainers », push forcé interdit ;
#   - fusion par MR, fils de discussion résolus obligatoires, branche source supprimée à la fusion ;
#   - méthode « merge commit with semi-linear history » (rebase_merge), squash autorisé ;
#   - messages des suggestions et des fusions compatibles avec commitlint.
#
# Jeton : ~/.config/workbook/gitlab-admin.token (ou WB_GITLAB_ADMIN_TOKEN_FILE), portée api.
# Le jeton ne passe ni sur la ligne de commande ni dans la liste des processus.
# Limite de GitLab CE : on ne peut pas modifier les niveaux d'accès d'une protection existante
# (allowed_to_push est réservé à Premium) ; le script supprime puis recrée la protection de main.
set -euo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"

usage() { echo "Usage : $0 GROUPE/PROJET [--ff] [--pipeline-obligatoire] [--dry-run]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
projet="$1"; shift
methode="rebase_merge"; pipeline=""; dry=0
while (( $# > 0 )); do
  case "$1" in
    --ff)                   methode="ff" ;;
    --pipeline-obligatoire) pipeline="true" ;;
    --dry-run)              dry=1 ;;
    *)                      usage ;;
  esac
  shift
done

for c in curl jq; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }; done
[[ -r "$JETON_FICHIER" ]] || { echo "jeton illisible : $JETON_FICHIER" >&2; exit 1; }

# api METHODE CHEMIN [JSON] — appel de l'API ; arrêt avec le message de GitLab en cas d'erreur
api() {
  local methode="$1" chemin="$2" json="${3:-}" corps code
  if (( dry )) && [[ "$methode" != GET ]]; then
    printf '[dry-run] %s %s %s\n' "$methode" "$chemin" "$json" >&2
    echo '{}'
    return 0
  fi
  corps="$(mktemp)"
  code="$(curl -sS -o "$corps" -w '%{http_code}' --max-time 30 -X "$methode" \
    -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(tr -d '[:space:]' < "$JETON_FICHIER")") \
    -H 'Content-Type: application/json' ${json:+--data-binary "$json"} \
    "$URL/api/v4/$chemin")"
  if [[ "$code" != 2* ]]; then
    echo "erreur : $methode $chemin → HTTP $code : $(head -c 300 "$corps")" >&2
    rm -f "$corps"
    return 1
  fi
  cat "$corps"
  rm -f "$corps"
}

p="$(jq -rn --arg s "$projet" '$s|@uri')"
info="$(api GET "projects/$p")"
[[ "$(jq -r .default_branch <<<"$info")" == main ]] \
  || { echo "erreur : la branche par défaut de $projet n'est pas main" >&2; exit 1; }

# 1. Réglages des merge requests
reglages="$(jq -nc --arg m "$methode" --arg pl "$pipeline" '{
  merge_method: $m,
  squash_option: "default_off",
  only_allow_merge_if_all_discussions_are_resolved: true,
  remove_source_branch_after_merge: true,
  suggestion_commit_message: "chore(revue): appliquer %{suggestions_count} suggestion(s) de revue",
  merge_commit_template: "Merge branch '\''%{source_branch}'\'' into '\''%{target_branch}'\''\n\n%{title}\n\n%{issues}\n\nSee merge request %{reference}\n\n%{approved_by}"
} + (if $pl == "true" then {only_allow_merge_if_pipeline_succeeds: true, allow_merge_on_skipped_pipeline: false} else {} end)')"
api PUT "projects/$p" "$reglages" >/dev/null
echo "OK  réglages des MR de $projet (méthode : $methode${pipeline:+, pipeline obligatoire})"

# 2. Protection de main (supprimer puis recréer si elle ne correspond pas)
voulu='{"name":"main","push_access_level":0,"merge_access_level":40,"allow_force_push":false}'
if actuel="$(api GET "projects/$p/protected_branches/main" 2>/dev/null)"; then
  if jq -e 'all(.push_access_levels[]; .access_level == 0)
            and all(.merge_access_levels[]; .access_level == 40)
            and .allow_force_push == false' <<<"$actuel" >/dev/null; then
    echo "OK  main déjà protégée selon la règle"
    exit 0
  fi
  echo "..  main protégée autrement : suppression puis recréation (quelques secondes sans protection)"
  api DELETE "projects/$p/protected_branches/main" >/dev/null
fi
api POST "projects/$p/protected_branches" "$voulu" >/dev/null
echo "OK  main protégée : push personne, fusion Maintainers, push forcé interdit"
