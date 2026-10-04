# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes passées entre apostrophes à bash -c
#
# check-E18.sh — M01-E18 : correctif urgent avec un worktree, sans perdre le travail en cours
# Lancé depuis adm01. Lecture seule (clone $WB_SRC/labo-worktrees, API GitLab).

title "M01-E18 — Worktrees : un correctif urgent sans abandonner son travail"
require_cmd curl jq git

_m01_clone="${WB_SRC:-$HOME/src}/labo-worktrees"
_m01_etat="$HOME/.local/state/workbook/ressources/M01-E18.env"
_m01_g() { git -C "$_m01_clone" "$@"; }

check_cmd "le clone $_m01_clone existe (ressources/M01-E18/fabriquer-depot.sh)" test -d "$_m01_clone/.git"

if [[ -d "$_m01_clone/.git" ]]; then
  # --- Le correctif est livré ------------------------------------------------------------------
  _m01_script="$(gitlab_api "projects/formation%2Fgit-labo/repository/files/worktrees%2Fverifier-sauvegardes.sh/raw?ref=main" 2>/dev/null)" || _m01_script=""
  check_cmd "main de formation/git-labo : le calcul de l'âge est en heures" \
    grep -Eq '/[[:space:]]*3600' <<<"$_m01_script"
  check_cmd "main de formation/git-labo : verifier-sauvegardes.sh reste valide" bash -n <<<"$_m01_script"
  check_cmd "le correctif est passé par une merge request fusionnée" \
    test "$(gitlab_api "projects/formation%2Fgit-labo/merge_requests?state=merged&per_page=100" 2>/dev/null \
      | jq '[.[] | select(.source_branch | test("^(fix|hotfix|e18)/"))] | length' 2>/dev/null || echo 0)" -ge 1

  # --- Le travail en cours est intact ------------------------------------------------------------
  check_output "la copie de travail principale est toujours sur e18/rapport-capacite" '^e18/rapport-capacite$' \
    git -C "$_m01_clone" branch --show-current
  check_cmd "les 2 commits locaux de e18/rapport-capacite sont toujours là" \
    test "$(_m01_g rev-list --count origin/main..e18/rapport-capacite 2>/dev/null || echo 0)" -ge 2
  check_cmd "la modification indexée (synthèse par profil) est toujours dans l'index" \
    bash -c 'git -C "$1" diff --cached -- worktrees/capacite.md | grep -q "Synthèse par profil"' _ "$_m01_clone"
  check_cmd "la modification non indexée (BROUILLON-E18) est toujours hors de l'index" \
    bash -c 'git -C "$1" diff -- worktrees/capacite.md | grep -q "BROUILLON-E18"' _ "$_m01_clone"
  check_cmd "le fichier non suivi notes-brouillon.md est toujours présent" test -f "$_m01_clone/worktrees/notes-brouillon.md"

  # --- La copie principale n'a pas changé de branche, le worktree est rangé ----------------------
  _m01_sans_bascule() {
    local depart msgs total
    depart="$(sed -n 's/^REFLOG_DEPART=//p' "$_m01_etat" 2>/dev/null | tail -n 1)"
    [[ -n "$depart" ]] || return 1
    msgs="$(_m01_g reflog show --format=%gs HEAD)" || return 1
    total="$(wc -l <<<"$msgs")"
    # entrées postérieures à la préparation = les (total - départ) premières lignes
    awk -v n="$(( total - depart ))" \
      'NR <= n && /^checkout: moving from e18\/rapport-capacite to/ {trouve = 1} END {exit trouve}' <<<"$msgs"
  }
  check_cmd "la copie de travail principale n'a jamais quitté e18/rapport-capacite pendant le correctif" _m01_sans_bascule
  check_cmd "plus aucun worktree supplémentaire (git worktree list)" \
    test "$(_m01_g worktree list --porcelain | grep -c '^worktree ')" -eq 1
  check_cmd "aucune entrée de worktree orpheline (git worktree prune)" \
    bash -c '! git -C "$1" worktree prune --dry-run -v 2>&1 | grep -q .' _ "$_m01_clone"
else
  skip "correctif et travail en cours" "clone absent"
fi
