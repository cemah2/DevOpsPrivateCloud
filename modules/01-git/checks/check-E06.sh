# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes évaluées par bash -c
#
# check-E06.sh — M01-E06 : migration de ~/medisphere vers plateforme/medisphere.
# Lancé depuis adm01. Lecture seule : API GitLab (jeton des checks), dépôt local (sans fetch :
# on compare avec les références de suivi telles qu'elles sont), connexion SSH « git@ » de test.

title "M01-E06 — Migrer ~/medisphere vers GitLab"
require_cmd curl jq git ssh

_m01_depot="${WB_DEPOT:-$HOME/medisphere}"
_m01_api="projects/plateforme%2Fmedisphere"

_m01_jq() {
  local desc="$1" filtre="$2" json="$3"; shift 3
  check_cmd "$desc" jq -e "$@" "$filtre" <<<"${json:-null}"
}

# --- Projet sur la forge -------------------------------------------------------------------
_m01_proj="$(gitlab_api "$_m01_api" 2>/dev/null || true)"
_m01_jq "projet plateforme/medisphere présent et privé" '.visibility == "private"' "$_m01_proj"
_m01_jq "branche par défaut du projet : main" '.default_branch == "main"' "$_m01_proj"

# --- Dépôt local --------------------------------------------------------------------------
check_output "origin de $_m01_depot = plateforme/medisphere sur git01" \
  'git01\.par1\.medisphere\.internal[:/]plateforme/medisphere(\.git)?$' git -C "$_m01_depot" remote get-url origin
check_output "branche locale courante : main" '^main$' git -C "$_m01_depot" branch --show-current
check_cmd "main locale suit origin/main" \
  bash -c '[ "$(git -C "$1" rev-parse --abbrev-ref main@{upstream} 2>/dev/null)" = origin/main ]' _ "$_m01_depot"
check_output "aucun commit local de main en attente de push" '^0$' \
  git -C "$_m01_depot" rev-list --count origin/main..main
check_output "arbre de travail propre" '^$' git -C "$_m01_depot" status --porcelain

# --- Étiquette socle-v0 : même objet des deux côtés ------------------------------------------
_m01_tag="$(gitlab_api "$_m01_api/repository/tags/socle-v0" 2>/dev/null || true)"
_m01_jq "socle-v0 sur la forge = même objet qu'en local (type et empreinte)" '.target == $t' "$_m01_tag" \
  --arg t "$(git -C "$_m01_depot" rev-parse -q --verify refs/tags/socle-v0 2>/dev/null)"
_m01_jq "socle-v0 sur la forge désigne le même commit qu'en local" '.commit.id == $c' "$_m01_tag" \
  --arg c "$(git -C "$_m01_depot" rev-parse -q --verify 'socle-v0^{commit}' 2>/dev/null)"
# compare from=main to=socle-v0 : commits de socle-v0 absents de main (aucun attendu)
_m01_jq "main sur la forge contient tout l'historique de socle-v0" \
  '.commits != null and (.commits | length) == 0' \
  "$(gitlab_api "$_m01_api/repository/compare?from=main&to=socle-v0" 2>/dev/null || true)"

# --- Accès SSH ------------------------------------------------------------------------------
_m01_cle="$(cut -d' ' -f2 "$HOME/.ssh/id_ed25519.pub" 2>/dev/null)"
_m01_jq "ta clé de connexion (~/.ssh/id_ed25519.pub) est déclarée dans ton profil" \
  'any(.[]; .key | split(" ")[1] == $k)' "$(gitlab_api user/keys 2>/dev/null || true)" --arg k "${_m01_cle:-absente}"
check_output "ssh -T git@git01.par1.medisphere.internal t'accueille par ton identifiant" \
  "Welcome to GitLab, @${WB_MOI:-<WB_MOI vide>}!" \
  ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -T git@git01.par1.medisphere.internal

# --- Contenu publié et sauvegarde -------------------------------------------------------------
check_cmd "docs/socle/inventaire.md sur la forge (main) mentionne git01 et 10.10.20.12" \
  bash -c 'grep -q git01 <<<"$1" && grep -q "10\.10\.20\.12" <<<"$1"' \
  _ "$(gitlab_api "$_m01_api/repository/files/docs%2Fsocle%2Finventaire%2Emd/raw?ref=main" 2>/dev/null)"
check_cmd "bundle de sauvegarde ~/medisphere-avant-migration.bundle valide" \
  git -C "$_m01_depot" bundle verify -q "$HOME/medisphere-avant-migration.bundle"
