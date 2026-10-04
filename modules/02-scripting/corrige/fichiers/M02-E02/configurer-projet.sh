#!/usr/bin/env bash
# configurer-projet.sh — crée et configure un projet de la plateforme par l'API GitLab (M02-E02).
#
# Applique la « configuration standard » de la plateforme (M01-E11, E24, E25) :
# projet privé initialisé sur main, fusion par MR avec pipeline réussi et discussions
# résolues, main protégée (push : personne ; fusion : Maintainers), étiquettes v*
# protégées, jeton de projet bot-release et variable CI GITLAB_TOKEN (protégée, masquée).
#
# Usage   : configurer-projet.sh GROUPE/PROJET        (ex. plateforme/outils)
# Jeton   : jeton d'administration de M01-E05/E20 (portée api), lu dans
#           $WB_GITLAB_ADMIN_TOKEN_FILE (défaut ~/.config/workbook/gitlab-admin.token).
# Variables facultatives : WB_GITLAB_URL, MERGE_METHOD (rebase_merge ou ff : reprends
#           le choix argumenté en M01-E11).
# Rejouable : chaque étape vérifie d'abord l'état existant.
# Codes retour : 0 succès, 1 erreur, 2 usage.
set -euo pipefail
umask 077

readonly GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
readonly JETON_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
readonly MERGE_METHOD="${MERGE_METHOD:-rebase_merge}"

journal() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }
die() {
  journal "ERREUR : $*"
  exit 1
}

(($# == 1)) && [[ "$1" == */* ]] || {
  echo "Usage : ${0##*/} GROUPE/PROJET" >&2
  exit 2
}
[[ "$MERGE_METHOD" == rebase_merge || "$MERGE_METHOD" == ff ]] \
  || die "MERGE_METHOD doit valoir rebase_merge ou ff"
projet="$1"
groupe="${projet%/*}"
nom="${projet##*/}"

for c in curl jq; do command -v "$c" >/dev/null || die "outil manquant : $c"; done
[[ -r "$JETON_FICHIER" ]] || die "jeton d'administration illisible : $JETON_FICHIER"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
# En-tête dans un fichier (curl -H @fichier) : le jeton n'apparaît pas dans « ps ».
printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_FICHIER")" >"$tmp/entete"

uri() { jq -rn --arg v "$1" '$v | @uri'; }

# api MÉTHODE CHEMIN [options curl…] — corps de la réponse sur stdout ; échec si HTTP ≥ 400.
api() {
  local methode="$1" chemin="$2"
  shift 2
  curl -sS --fail-with-body --max-time 30 -X "$methode" -H "@$tmp/entete" "$@" \
    "$GITLAB_URL/api/v4/$chemin" || die "$methode $chemin a échoué"
}

# code_http CHEMIN — code HTTP d'un GET (pour tester une existence sans échouer).
code_http() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -H "@$tmp/entete" \
    "$GITLAB_URL/api/v4/$1"
}

# --- 1. Projet ---------------------------------------------------------------
p="projects/$(uri "$projet")"
if [[ "$(code_http "$p")" == 200 ]]; then
  journal "projet $projet : existe déjà"
else
  groupe_id="$(api GET "groups/$(uri "$groupe")" | jq -r '.id')"
  journal "projet $projet : création (privé, initialisé sur main)"
  api POST projects \
    --data-urlencode "name=$nom" --data-urlencode "path=$nom" \
    --data-urlencode "namespace_id=$groupe_id" --data-urlencode "visibility=private" \
    --data-urlencode "initialize_with_readme=true" --data-urlencode "default_branch=main" \
    --data-urlencode "description=Outils d'exploitation de l'équipe Plateforme" >/dev/null
fi

# --- 2. Règles de fusion -----------------------------------------------------
journal "règles de fusion : $MERGE_METHOD, pipeline réussi et discussions résolues obligatoires"
api PUT "$p" \
  --data-urlencode "merge_method=$MERGE_METHOD" \
  --data-urlencode "only_allow_merge_if_pipeline_succeeds=true" \
  --data-urlencode "only_allow_merge_if_all_discussions_are_resolved=true" \
  --data-urlencode "remove_source_branch_after_merge=true" \
  --data-urlencode "squash_option=default_off" >/dev/null

# --- 3. Branche main protégée ------------------------------------------------
# GitLab protège la branche par défaut à la création, avec les réglages par défaut
# de l'instance. On remplace cette protection par la nôtre si elle diffère.
voulu='{"push":[0],"merge":[40],"force":false}'
actuel="$(api GET "$p/protected_branches" | jq -c '
  map(select(.name == "main"))[0]
  | if . == null then null else
      {push: [.push_access_levels[].access_level] | sort,
       merge: [.merge_access_levels[].access_level] | sort,
       force: .allow_force_push} end')"
if [[ "$actuel" == "$voulu" ]]; then
  journal "main : protection déjà conforme"
else
  if [[ "$actuel" != null ]]; then
    journal "main : remplacement de la protection existante ($actuel)"
    api DELETE "$p/protected_branches/main" >/dev/null
  fi
  api POST "$p/protected_branches" \
    --data-urlencode "name=main" --data-urlencode "push_access_level=0" \
    --data-urlencode "merge_access_level=40" --data-urlencode "allow_force_push=false" >/dev/null
  journal "main : protégée (push : personne ; fusion : Maintainers)"
fi

# --- 4. Étiquettes v* protégées ----------------------------------------------
if api GET "$p/protected_tags" | jq -e 'any(.[]; .name == "v*")' >/dev/null; then
  journal "étiquettes v* : déjà protégées"
else
  api POST "$p/protected_tags" \
    --data-urlencode "name=v*" --data-urlencode "create_access_level=40" >/dev/null
  journal "étiquettes v* : protégées (création : Maintainers)"
fi

# --- 5. Jeton de projet bot-release et variable GITLAB_TOKEN -----------------
if api GET "$p/access_tokens" | jq -e 'any(.[]; .name == "bot-release" and .active)' >/dev/null; then
  journal "jeton bot-release : déjà actif (rotation : révoque-le puis relance ce script)"
else
  expiration="$(date -d '+1 year -1 day' +%F)"
  journal "jeton bot-release : création (Maintainer, api + write_repository, expire le $expiration)"
  # Le secret ne passe que par un fichier 600 et l'entrée standard de curl.
  api POST "$p/access_tokens" \
    --data-urlencode "name=bot-release" --data-urlencode "access_level=40" \
    --data-urlencode "scopes[]=api" --data-urlencode "scopes[]=write_repository" \
    --data-urlencode "expires_at=$expiration" | jq -r '.token' >"$tmp/jeton"
  [[ -s "$tmp/jeton" && "$(<"$tmp/jeton")" != null ]] || die "jeton bot-release non reçu"
  if [[ "$(code_http "$p/variables/GITLAB_TOKEN")" == 200 ]]; then
    methode=PUT chemin="$p/variables/GITLAB_TOKEN"
  else
    methode=POST chemin="$p/variables"
  fi
  tr -d '\n' <"$tmp/jeton" | api "$methode" "$chemin" \
    --data-urlencode "key=GITLAB_TOKEN" --data-urlencode "value@-" \
    --data-urlencode "protected=true" --data-urlencode "masked=true" >/dev/null
  journal "variable CI GITLAB_TOKEN : enregistrée (protégée, masquée)"
fi

journal "projet $projet configuré : $GITLAB_URL/$projet"
