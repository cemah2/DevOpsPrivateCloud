# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M01-E42 « Panne : tout mon travail a disparu »
#
# Le script (re)fabrique le dépôt de Lucas, ~/src/labo-e42 (ressources/M01-E42/fabriquer-depot.sh :
# branche feature/rotation-jetons avec 4 commits jamais poussés, 1 stash), en garde une archive,
# puis rejoue la « fausse manœuvre » de Lucas :
#   1. git reset --hard HEAD~3 sur la branche (3 commits n'y sont plus) ;
#   2. git switch main puis git branch -D feature/rotation-jetons (branche supprimée) ;
#   3. git stash drop (notes de conception perdues) ;
#   4. nouveau script indexé (git add) jamais commité, puis git reset --hard (contenu perdu).
# Sauvegarde : ~/.local/state/workbook/M01-E42/depot-avant.tar (état juste avant la manœuvre).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

_E42_depot() { printf '%s\n' "${WB_SRC:-$HOME/src}/labo-e42"; }
_E42_g() { git -C "$(_E42_depot)" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_E42_preparer() {
  local d etat
  d="$(_E42_depot)"
  etat="$(m01_etat E42)"
  bash "$WB_ROOT/modules/01-git/ressources/M01-E42/fabriquer-depot.sh" --force "$d" >/dev/null || return 1
  tar -C "$(dirname "$d")" -cf "$etat/depot-avant.tar" "$(basename "$d")" "$(basename "$d")-origine.git"
}

panne_E42_v1() {
  _E42_preparer || return 1
  _E42_g reset -q --hard HEAD~3
}

panne_E42_v2() {
  _E42_preparer || return 1
  _E42_g switch -q main && _E42_g branch -q -D feature/rotation-jetons
}

panne_E42_v3() {
  _E42_preparer || return 1
  _E42_g stash drop -q
}

panne_E42_v4() {
  local d
  _E42_preparer || return 1
  d="$(_E42_depot)"
  cat > "$d/scripts/purge-jetons.sh" <<'EOF'
#!/usr/bin/env bash
# Purge des jetons révoqués depuis plus de 90 jours (mode simulation par défaut).
set -euo pipefail
projet="${1:?usage : purge-jetons.sh <id-projet> [--appliquer]}"
appliquer="${2:-}"
"$(dirname "$0")/lister-jetons.sh" "$projet" | while IFS=$'\t' read -r id nom expire; do
  if [ "$appliquer" = "--appliquer" ]; then
    echo "révocation de $id ($nom, $expire)"
  else
    echo "[simulation] révoquerait $id ($nom, $expire)"
  fi
done
EOF
  chmod +x "$d/scripts/purge-jetons.sh"
  _E42_g add scripts/purge-jetons.sh && _E42_g reset -q --hard
}

# Le travail perdu n'est plus atteignable depuis les références.
verifier_E42() {
  local tout
  tout="$(_E42_g log --all --format=%s 2>/dev/null)" || return 1
  case "${WB_VAR:-}" in
    1|2) ! grep -qF "feat(jetons): produire le rapport hebdomadaire des expirations" <<<"$tout" ;;
    3) ! _E42_g log --all -p --diff-merges=first-parent 2>/dev/null | grep -qF "Conception retenue" ;;
    4) [[ ! -e "$(_E42_depot)/scripts/purge-jetons.sh" ]] ;;
    *) return 1 ;;
  esac
}

annuler_E42() {
  local d etat
  d="$(_E42_depot)"
  etat="$(m01_etat E42)"
  if [[ -f "$etat/depot-avant.tar" ]]; then
    rm -rf "$d" "$d-origine.git"
    tar -C "$(dirname "$d")" -xf "$etat/depot-avant.tar" && rm -f "$etat/depot-avant.tar"
  fi
  return 0
}

resume_E42() {
  echo "Lucas a « tout perdu » dans ~/src/labo-e42 après une fausse manœuvre Git (il ne sait plus laquelle)."
}

symptome_E42() {
  wb_symptome "Ticket INC-2787 — De : Lucas Martin" \
    "Au secours : j'ai voulu « nettoyer » mon dépôt ~/src/labo-e42 avant de pousser, et une" \
    "partie de mon travail a disparu (je ne sais plus exactement ce que j'ai tapé, j'ai" \
    "recopié des commandes d'un forum). Je n'avais encore rien poussé de ma branche" \
    "feature/rotation-jetons. Est-ce que c'est récupérable ? Je n'ose plus rien toucher." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 01 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E42 4 "$@"; }
fi
