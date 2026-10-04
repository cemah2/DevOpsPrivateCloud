#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# fabriquer-depot.sh — M01-E12 : prépare une branche « en vrac » dans formation/git-labo.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E12/fabriquer-depot.sh                 # première préparation
#   modules/01-git/ressources/M01-E12/fabriquer-depot.sh --reinitialiser # remet la branche à l'état initial
#
# Effets sur formation/git-labo (via un clone temporaire, ton clone de travail n'est pas touché) :
#   - main : commit « docs(rebase): consignes de l'atelier » (rebase/README.md), une seule fois ;
#   - branche e12/verif-sauvegardes : 7 commits désordonnés, partant de ce commit (poussée en force) ;
#   - main : commit « feat(rebase): fonctions communes de journalisation » (rebase/commun.sh), une seule fois.
# Les commits de main sont signés Karim Benali, ceux de la branche portent ton identité Git.
# shellcheck disable=SC2016  # le script écrit du code shell : les $ sont voulus littéraux
set -euo pipefail

WB_EX="M01-E12"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"

PROJET="formation/git-labo"
BRANCHE="e12/verif-sauvegardes"
KARIM=(-c "user.name=Karim Benali" -c "user.email=karim.benali@medisphere.internal")

reinit=0
case "${1:-}" in
  "") ;;
  --reinitialiser) reinit=1 ;;
  *) echo "Usage : $0 [--reinitialiser]" >&2; exit 2 ;;
esac

gl_prerequis
gl_cloner_temp "$PROJET" DEPOT
trap 'rm -rf "$(dirname "$DEPOT")"' EXIT
cd "$DEPOT"
git config user.name >/dev/null || gl_erreur "identité Git absente (git config --global user.name, voir M01-E03)"

if git ls-remote --exit-code --heads origin "$BRANCHE" >/dev/null && (( ! reinit )); then
  gl_erreur "la branche $BRANCHE existe déjà sur $PROJET. Relance avec --reinitialiser pour repartir de zéro."
fi

# --- Le script vérifié, dans ses états successifs -------------------------------------
# script_verif OPTION(0|1) FI(0|1) DEBUG(0|1) DATASTORE_PAR_DEFAUT
script_verif() {
  local opt="$1" fi="$2" debug="$3" ds="$4"
  cat <<'EOF'
#!/usr/bin/env bash
# verif-pbs.sh — vérifie l'âge de la dernière sauvegarde de chaque VM sur PBS.
EOF
  if (( opt )); then echo "# Usage : verif-pbs.sh [--datastore NOM] [--seuil-heures N]"; fi
  echo "set -euo pipefail"
  if (( debug )); then echo "set -x"; fi
  echo
  if (( opt )); then echo "DATASTORE=\"$ds\""; fi
  cat <<'EOF'
SEUIL_HEURES=26
PBS_HOTE="pbs01.par2.medisphere.internal"
EOF
  if (( opt )); then
    cat <<'EOF'

usage() { echo "Usage : $0 [--datastore NOM] [--seuil-heures N]" >&2; exit 2; }

while (( $# > 0 )); do
  case "$1" in
    --datastore)    DATASTORE="${2:?}"; shift 2 ;;
    --seuil-heures) SEUIL_HEURES="${2:?}"; shift 2 ;;
    *)              usage ;;
  esac
done
EOF
  fi
  cat <<'EOF'

if [[ -z "${PBS_PASSWORD:-}" ]]; then
  echo "variable PBS_PASSWORD absente (secret à charger depuis ~/.config/workbook)" >&2
  exit 1
EOF
  if (( fi )); then echo "fi"; fi
  if (( debug )); then echo "echo \"DEBUG token=\$PBS_PASSWORD\" >&2"; fi
  echo
  if (( opt )); then
    echo 'export PBS_REPOSITORY="root@pam@${PBS_HOTE}:${DATASTORE}"'
  else
    echo 'export PBS_REPOSITORY="root@pam@${PBS_HOTE}:ds-lab"'
  fi
  cat <<'EOF'
maintenant="$(date +%s)"
proxmox-backup-client snapshot list --output-format json \
  | jq -r --argjson now "$maintenant" --argjson seuil "$SEUIL_HEURES" '
      group_by(."backup-type" + "/" + ."backup-id")[]
      | max_by(."backup-time")
      | select(($now - ."backup-time") > $seuil * 3600)
      | "\(."backup-type")/\(."backup-id") : dernière sauvegarde trop ancienne"'
EOF
}

ecrire() { mkdir -p rebase; script_verif "$@" > rebase/verif-pbs.sh; chmod +x rebase/verif-pbs.sh; }
commit() { git add -A rebase; git commit -q -m "$1"; }

# --- main : consignes de l'atelier (une fois) ---------------------------------------------
if [[ ! -f rebase/README.md ]]; then
  mkdir -p rebase
  cat > rebase/README.md <<'EOF'
# Atelier rebase (M01-E12)

Ce dossier sert à l'exercice de rebase interactif. La branche `e12/verif-sauvegardes`
part du commit qui a créé ce fichier.
EOF
  git add rebase/README.md
  git "${KARIM[@]}" commit -q -m "docs(rebase): consignes de l'atelier"
  git push -q origin HEAD:main || gl_erreur "push sur main refusé : vérifie la protection de main sur $PROJET (voir l'énoncé)"
fi
base="$(git log --diff-filter=A --format=%H -1 -- rebase/README.md)"

# --- La branche en vrac ---------------------------------------------------------------------
git switch -q -C "$BRANCHE" "$base"
ecrire 0 0 0 local;      commit "wip"
ecrire 1 0 0 local;      commit "ajout option datastore"
ecrire 1 1 0 local;      commit "fix typo"
ecrire 1 1 1 local;      commit "debug"
cat > rebase/verif-pbs.md <<'EOF'
# verif-pbs.sh — mode d'emploi

Vérifie que chaque VM du lab a une sauvegarde de moins de 26 heures sur `pbs01`.

    PBS_PASSWORD=... rebase/verif-pbs.sh [--datastore ds-lab] [--seuil-heures 26]

Le mot de passe (ou le secret du jeton) ne s'écrit jamais dans le script : il vient de
l'environnement, chargé depuis `~/.config/workbook/`.
Code de sortie : 0 ; la liste des VMs en retard s'affiche sur la sortie standard.
EOF
commit "doc"
ecrire 1 1 0 local;      commit "nettoyage"
ecrire 1 1 0 ds-lab;     commit "fixup! ajout option datastore"
git push -q --force origin "$BRANCHE"

# --- main avance (une fois) -------------------------------------------------------------------
git switch -q main
if [[ ! -f rebase/commun.sh ]]; then
  cat > rebase/commun.sh <<'EOF'
# shellcheck shell=bash
# commun.sh — fonctions de journalisation partagées par les scripts de l'atelier.
log()    { printf '%s %s\n' "$(date +%FT%T)" "$*" >&2; }
erreur() { log "ERREUR : $*"; exit 1; }
EOF
  git add rebase/commun.sh
  git "${KARIM[@]}" commit -q -m "feat(rebase): fonctions communes de journalisation"
  git push -q origin HEAD:main
fi

gl_msg "Prêt : la branche $BRANCHE (7 commits) attend ton rebase dans $PROJET."
gl_msg "Dans ton clone : git -C $WB_SRC/git-labo fetch --prune"
