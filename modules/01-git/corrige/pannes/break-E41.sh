# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M01-E41 « Panne : le dépôt local est corrompu »
#
# Le script (re)fabrique d'abord le dépôt de travail de Lucas, ~/src/labo-e41 (WB_SRC), avec
# ressources/M01-E41/fabriquer-depot.sh : 3 commits jamais poussés, 1 stash, 1 modification en
# cours. Il en garde une archive saine, puis simule l'effet d'une coupure de courant :
#   1. objet libre (blob de HEAD:scripts/sauvegarde-gitlab.sh) tronqué à 0 octet ;
#   2. référence refs/heads/feature/sauvegarde-gitlab (branche courante) tronquée à 0 octet ;
#   3. en-tête du fichier d'index (.git/index) écrasé par des zéros ;
#   4. fichier .git/HEAD tronqué à 0 octet (Git ne reconnaît plus le dépôt).
# Sauvegarde : ~/.local/state/workbook/M01-E41/depot-sain.tar (dépôt + origine), restaurée par
# l'annulation. Aucune action réseau, rien hors de WB_SRC.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

_E41_depot() { printf '%s\n' "${WB_SRC:-$HOME/src}/labo-e41"; }

# Fabrication + archive saine (commune à toutes les variantes).
_E41_preparer() {
  local d etat
  d="$(_E41_depot)"
  etat="$(m01_etat E41)"
  bash "$WB_ROOT/modules/01-git/ressources/M01-E41/fabriquer-depot.sh" --force "$d" >/dev/null || return 1
  tar -C "$(dirname "$d")" -cf "$etat/depot-sain.tar" "$(basename "$d")" "$(basename "$d")-origine.git"
}

panne_E41_v1() {
  local d b f
  _E41_preparer || return 1
  d="$(_E41_depot)"
  b="$(git -C "$d" rev-parse HEAD:scripts/sauvegarde-gitlab.sh)" || return 1
  f="$d/.git/objects/${b:0:2}/${b:2}"
  [[ -f "$f" ]] || return 1
  chmod u+w "$f" && : > "$f"
}

panne_E41_v2() {
  local d
  _E41_preparer || return 1
  d="$(_E41_depot)"
  [[ -f "$d/.git/refs/heads/feature/sauvegarde-gitlab" ]] || return 1
  : > "$d/.git/refs/heads/feature/sauvegarde-gitlab"
}

panne_E41_v3() {
  local d
  _E41_preparer || return 1
  d="$(_E41_depot)"
  printf '\0\0\0\0\0\0\0\0\0\0\0\0' | dd of="$d/.git/index" bs=1 count=12 conv=notrunc status=none
}

panne_E41_v4() {
  local d
  _E41_preparer || return 1
  d="$(_E41_depot)"
  : > "$d/.git/HEAD"
}

verifier_E41() {
  local d
  d="$(_E41_depot)"
  ! { git -C "$d" status --porcelain >/dev/null 2>&1 && git -C "$d" fsck --full >/dev/null 2>&1; }
}

# Le dépôt est-il déjà réparé (intègre, et rien de Lucas n'est perdu) ?
_E41_repare() {
  local d sujets
  d="$(_E41_depot)"
  git -C "$d" status --porcelain >/dev/null 2>&1 && git -C "$d" fsck --full >/dev/null 2>&1 || return 1
  sujets="$(git -C "$d" log --format=%s origin/main..feature/sauvegarde-gitlab 2>/dev/null)" || return 1
  [[ "$(grep -c . <<<"$sujets")" -ge 3 ]] || return 1
  git -C "$d" stash list 2>/dev/null | grep -qF 'essai option --dry-run'
}

annuler_E41() {
  local d etat
  d="$(_E41_depot)"
  etat="$(m01_etat E41)"
  if [[ -f "$etat/depot-sain.tar" ]]; then
    if _E41_repare; then
      # Réparation de l'apprenant conservée (y compris la branche poussée sur l'origine).
      rm -f "$etat/depot-sain.tar"
    else
      rm -rf "$d" "$d-origine.git"
      tar -C "$(dirname "$d")" -xf "$etat/depot-sain.tar" && rm -f "$etat/depot-sain.tar"
    fi
  fi
  return 0
}

resume_E41() {
  echo "Lucas : après une coupure de courant, son dépôt ~/src/labo-e41 renvoie des erreurs Git ; 3 commits non poussés, un stash et des modifications en cours sont en jeu."
}

# shellcheck disable=SC2088  # « ~ » affiché tel quel dans le ticket
symptome_E41() {
  wb_symptome "Ticket INC-2786 — De : Lucas Martin" \
    "Coupure de courant cette nuit sur mon poste (j'avais copié mon dépôt sur adm01 :" \
    "~/src/labo-e41). Depuis, Git m'affiche des erreurs que je ne comprends pas, selon les" \
    "commandes. J'ai 3 commits jamais poussés sur feature/sauvegarde-gitlab, un stash et des" \
    "modifications en cours dans le runbook. Surtout, ne me dis pas de re-cloner !" \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 01 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E41 4 "$@"; }
fi
