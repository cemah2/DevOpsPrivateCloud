#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E19 : prépare une branche de maintenance 1.x dans formation/git-labo.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E19/fabriquer-depot.sh
#
# Effets sur formation/git-labo (via un clone temporaire), une seule fois :
#   - main : version 1.4 de cherry/sauvegarde-vm.sh ;
#   - branche e19/1.x (maintenance de la 1.x) créée à ce point, avec un commit propre à la maintenance ;
#   - main : 5 commits de Julien Petit et Karim Benali (fonctions, correctifs, refactorisation).
# shellcheck disable=SC2016  # le script écrit du code shell : les $ sont voulus littéraux
set -euo pipefail

WB_EX="M01-E19"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"

PROJET="formation/git-labo"
JULIEN=(-c "user.name=Julien Petit" -c "user.email=julien.petit@medisphere.internal")
KARIM=(-c "user.name=Karim Benali" -c "user.email=karim.benali@medisphere.internal")
F="cherry/sauvegarde-vm.sh"

[[ $# -eq 0 ]] || { echo "Usage : $0" >&2; exit 2; }
gl_prerequis
gl_cloner_temp "$PROJET" DEPOT
trap 'rm -rf "$(dirname "$DEPOT")"' EXIT
cd "$DEPOT"

if git ls-remote --exit-code --heads origin e19/1.x >/dev/null; then
  gl_erreur "la branche e19/1.x existe déjà sur $PROJET : l'atelier est prêt (rien à refaire)."
fi

# script NOM_FONCTION_CONTROLE PLAGE(0|1) MESSAGE_VZDUMP(0|1) POOL(0|1) SYSLOG(0|1)
script() {
  local f="$1" plage="$2" msg="$3" pool="$4" syslog="$5"
  cat <<'EOF'
#!/usr/bin/env bash
# sauvegarde-vm.sh — sauvegarde une VM du lab vers PBS (outil de l'équipe MédiAgenda).
set -euo pipefail

STOCKAGE="pbs-par2"

EOF
  printf '%s() {\n' "$f"
  echo '  [[ "$1" =~ ^[0-9]+$ ]] || { echo "VMID invalide : $1" >&2; exit 2; }'
  if (( plage )); then
    echo '  (( $1 >= 1000 && $1 <= 9099 )) || { echo "VMID hors des plages du workbook : $1" >&2; exit 2; }'
  fi
  cat <<'EOF'
}

sauvegarder() {
  local vmid="$1"
EOF
  printf '  %s "$vmid"\n' "$f"
  if (( msg )); then
    printf '%s %s\n' '  vzdump "$vmid" --storage "$STOCKAGE" --mode snapshot' "\\"
    echo '    || { echo "échec de vzdump pour la VM $vmid (voir le journal de la tâche sur pve01)" >&2; exit 1; }'
  else
    echo '  vzdump "$vmid" --storage "$STOCKAGE" --mode snapshot'
  fi
  if (( syslog )); then echo '  logger -t sauvegarde-vm "VM $vmid sauvegardée vers $STOCKAGE"'; fi
  echo "}"
  echo
  if (( pool )); then
    cat <<'EOF'
if [[ "${1:-}" == --pool ]]; then
  [[ $# -eq 2 ]] || { echo "Usage : $0 --pool POOL" >&2; exit 2; }
  for vmid in $(pvesh get "/pools/$2" --output-format json | jq -r '.members[] | select(.type == "qemu") | .vmid'); do
    sauvegarder "$vmid"
  done
else
  [[ $# -eq 1 ]] || { echo "Usage : $0 VMID | --pool POOL" >&2; exit 2; }
  sauvegarder "$1"
fi
EOF
  else
    cat <<'EOF'
[[ $# -eq 1 ]] || { echo "Usage : $0 VMID" >&2; exit 2; }
sauvegarder "$1"
EOF
  fi
}

mkdir -p cherry
script verifier_vmid 0 0 0 0 > "$F"; chmod +x "$F"
git add cherry
git "${JULIEN[@]}" commit -q -m "feat(cherry): script de sauvegarde unitaire (version 1.4)"
git push -q origin HEAD:main || gl_erreur "push sur main refusé : vérifie la protection de main sur $PROJET (voir l'énoncé)"

git switch -q -c e19/1.x
cat > cherry/NOTES-1.x.md <<'EOF'
# sauvegarde-vm.sh — branche de maintenance 1.x

Branche utilisée par l'équipe MédiAgenda jusqu'à la fin du trimestre.
Règle : uniquement des correctifs (`fix`), rétroportés depuis main avec `git cherry-pick -x`.
EOF
git add cherry/NOTES-1.x.md
git "${JULIEN[@]}" commit -q -m "docs(cherry): règles de la branche de maintenance 1.x"
git push -q origin e19/1.x

git switch -q main
script verifier_vmid 0 0 1 0 > "$F"
git "${JULIEN[@]}" commit -q -am "feat(cherry): option --pool pour sauvegarder tout un pool"
script verifier_vmid 1 0 1 0 > "$F"
git "${KARIM[@]}" commit -q -am "fix(cherry): refuser un VMID hors des plages du workbook"
script controler_vmid 1 0 1 0 > "$F"
git "${JULIEN[@]}" commit -q -am "refactor(cherry): renommer verifier_vmid en controler_vmid"
script controler_vmid 1 1 1 0 > "$F"
git "${KARIM[@]}" commit -q -am "fix(cherry): message clair quand vzdump échoue"
script controler_vmid 1 1 1 1 > "$F"
git "${JULIEN[@]}" commit -q -am "feat(cherry): journaliser chaque sauvegarde dans syslog"
git push -q origin HEAD:main

gl_msg "Prêt : main a avancé de 5 commits depuis la création de e19/1.x dans $PROJET."
gl_msg "Dans ton clone : git -C $WB_SRC/git-labo fetch --prune"
