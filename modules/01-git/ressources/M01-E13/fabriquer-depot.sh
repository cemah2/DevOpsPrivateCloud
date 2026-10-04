#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E13 : prépare des conflits dans formation/git-labo.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E13/fabriquer-depot.sh                 # première préparation
#   modules/01-git/ressources/M01-E13/fabriquer-depot.sh --reinitialiser # remet ta branche à l'état initial
#
# Effets sur formation/git-labo (via un clone temporaire) :
#   - main : commit de base « docs(conflits): inventaire et script de l'atelier » (une fois) ;
#   - branche e13/inventaire-runner01 : 3 commits à ton nom, partant de ce commit (poussée en force) ;
#   - main : 2 commits de Karim (inventaire, renommage d'une variable du script), une fois.
# shellcheck disable=SC2016  # le script écrit du code shell : les $ sont voulus littéraux
set -euo pipefail

WB_EX="M01-E13"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"

PROJET="formation/git-labo"
BRANCHE="e13/inventaire-runner01"
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
git config user.name >/dev/null || gl_erreur "identité Git absente (voir M01-E03)"

if git ls-remote --exit-code --heads origin "$BRANCHE" >/dev/null && (( ! reinit )); then
  gl_erreur "la branche $BRANCHE existe déjà sur $PROJET. Relance avec --reinitialiser pour repartir de zéro."
fi

# --- Contenus ---------------------------------------------------------------------------------
# inventaire DNS01_RAM DNS01_ROLE LIGNES_EN_PLUS...
inventaire() {
  local ram="$1" role="$2"; shift 2
  cat <<'EOF'
# Inventaire de l'atelier conflits (M01-E13)

| Hôte | VMID | Adresse | vCPU | RAM | Rôle |
|---|---|---|---|---|---|
| gw01 | 1000 | 10.10.10.1 | 2 | 2 Go | Routeur, pare-feu, NAT |
| adm01 | 1001 | 10.10.10.10 | 2 | 4 Go | Poste d'administration |
EOF
  printf '| dns01 | 1002 | 10.10.20.10 | 1 | %s | %s |\n' "$ram" "$role"
  local l
  for l in "$@"; do printf '%s\n' "$l"; done
  cat <<'EOF'

Source de vérité provisoire : ce fichier sera remplacé par NetBox au module 06.
EOF
}

# sauvegarde VARIABLE_STOCKAGE AVEC_VERIFICATION(0|1) [VARIABLE_UTILISEE_PAR_LA_VERIFICATION]
sauvegarde() {
  local var="$1" verif="$2" var_verif="${3:-$1}"
  cat <<'EOF'
#!/usr/bin/env bash
# sauvegarde.sh — lance vzdump pour une liste de VMs du lab.
# Usage : sauvegarde.sh VMID...   (SIMULATION=1 pour afficher les commandes sans les lancer)
set -euo pipefail

EOF
  printf '%s="pbs-par2"\n' "$var"
  cat <<'EOF'
MODE="snapshot"
SIMULATION="${SIMULATION:-0}"

lancer() {
  if [[ "$SIMULATION" == 1 ]]; then echo "+ $*"; else "$@"; fi
}

controler_vmids() {
  local v
  (( $# > 0 )) || { echo "Usage : $0 VMID..." >&2; exit 2; }
  for v in "$@"; do
    [[ "$v" =~ ^(1[0-9]{3}|2[0-9]{3}|5[0-9]{3})$ ]] || { echo "VMID hors des plages du lab : $v" >&2; exit 2; }
  done
}
EOF
  if (( verif )); then
    cat <<EOF

verifier_stockage() {
  lancer pvesm status --storage "\$$var_verif" >/dev/null || { echo "stockage \$$var_verif indisponible" >&2; exit 1; }
}
EOF
  fi
  cat <<'EOF'

# --- Contrôles préalables ---
controler_vmids "$@"
EOF
  if (( verif )); then echo "verifier_stockage"; fi
  cat <<'EOF'

# --- Sauvegarde ---
EOF
  printf 'echo "Sauvegarde de %s VM(s) vers $%s"\n' '$#' "$var"
  cat <<'EOF'
for vmid in "$@"; do
EOF
  printf '  lancer vzdump "$vmid" --storage "$%s" --mode "$MODE"\n' "$var"
  echo "done"
}

ROLE_V1="DNS et DHCP (dnsmasq)"
ROLE_V2="DNS et DHCP (dnsmasq, provisoire jusqu'au M06)"
L_GIT01="| git01 | 1004 | 10.10.20.12 | 4 | 8 Go | GitLab CE |"
L_RUNNER01="| runner01 | 1007 | 10.10.20.15 | 2 | 4 Go | GitLab Runner (exécuteur shell) |"

# --- main : base de l'atelier (une fois) -------------------------------------------------------
if [[ ! -f conflits/inventaire.md ]]; then
  mkdir -p conflits
  inventaire "1 Go" "$ROLE_V1" > conflits/inventaire.md
  sauvegarde DEST 0 > conflits/sauvegarde.sh; chmod +x conflits/sauvegarde.sh
  git add conflits
  git "${KARIM[@]}" commit -q -m "docs(conflits): inventaire et script de l'atelier"
  git push -q origin HEAD:main || gl_erreur "push sur main refusé : vérifie la protection de main sur $PROJET (voir l'énoncé)"
fi
base="$(git log --diff-filter=A --format=%H -1 -- conflits/inventaire.md)"

# --- Ta branche ---------------------------------------------------------------------------------
git switch -q -C "$BRANCHE" "$base"
inventaire "1 Go" "$ROLE_V1" "$L_RUNNER01" > conflits/inventaire.md
git commit -q -am "docs(inventaire): ajouter runner01"
inventaire "2 Go" "$ROLE_V1" "$L_RUNNER01" > conflits/inventaire.md
git commit -q -am "docs(inventaire): corriger la mémoire de dns01"
sauvegarde DEST 1 > conflits/sauvegarde.sh
git commit -q -am "feat(sauvegarde): vérifier le stockage avant de sauvegarder"
git push -q --force origin "$BRANCHE"

# --- main avance : Karim (une fois) ---------------------------------------------------------
git switch -q main
if ! grep -q 'git01' conflits/inventaire.md; then
  inventaire "1 Go" "$ROLE_V2" "$L_GIT01" > conflits/inventaire.md
  git "${KARIM[@]}" commit -q -am "docs(inventaire): ajouter git01 et préciser le rôle de dns01"
  sauvegarde STOCKAGE 0 > conflits/sauvegarde.sh
  git "${KARIM[@]}" commit -q -am "refactor(sauvegarde): renommer DEST en STOCKAGE"
  git push -q origin HEAD:main
fi

gl_msg "Prêt : la branche $BRANCHE (3 commits) et main ont divergé dans $PROJET."
gl_msg "Dans ton clone : git -C $WB_SRC/git-labo fetch --prune"
