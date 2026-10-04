#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E18 : te met « au milieu d'un travail » dans un clone dédié.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E18/fabriquer-depot.sh
#
# Effets :
#   - formation/git-labo, main : commit de Karim ajoutant worktrees/verifier-sauvegardes.sh (une fois) ;
#   - $WB_SRC/labo-worktrees : nouveau clone de formation/git-labo, branche locale e18/rapport-capacite
#     avec 2 commits non poussés, une modification indexée, une modification non indexée
#     et un fichier non suivi (ton « travail en cours ») ;
#   - ~/.local/state/workbook/ressources/M01-E18.env : point de départ du journal des références (pour le check).
# Le script refuse d'écraser un dossier $WB_SRC/labo-worktrees existant.
set -euo pipefail

WB_EX="M01-E18"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"

PROJET="formation/git-labo"
CLONE="$WB_SRC/labo-worktrees"
KARIM=(-c "user.name=Karim Benali" -c "user.email=karim.benali@medisphere.internal")

[[ $# -eq 0 ]] || { echo "Usage : $0" >&2; exit 2; }
gl_prerequis
[[ ! -e "$CLONE" ]] || gl_erreur "$CLONE existe déjà. Pour recommencer : vérifie qu'il ne contient rien d'utile, supprime-le (et ses worktrees : git -C $CLONE worktree list), puis relance."

# --- main : le script de supervision défectueux (une fois) ------------------------------------
gl_cloner_temp "$PROJET" TMP
trap 'rm -rf "$(dirname "$TMP")"' EXIT
if [[ ! -f "$TMP/worktrees/verifier-sauvegardes.sh" ]]; then
  mkdir -p "$TMP/worktrees"
  cat > "$TMP/worktrees/verifier-sauvegardes.sh" <<'EOF'
#!/usr/bin/env bash
# verifier-sauvegardes.sh — alerte si la dernière sauvegarde d'une VM est trop ancienne.
# Lancé par cron à 2 h 30 sur adm01, après la tâche PBS « lab-nuit » de 1 h.
# Entrée : lignes « VMID HORODATAGE_UNIX » (dernière sauvegarde de chaque VM) sur l'entrée standard.
# Sortie : une ligne « ALERTE » par VM en retard ; code 1 s'il y a au moins une alerte.
set -euo pipefail

SEUIL_HEURES=26   # une sauvegarde par nuit, avec deux heures de marge

maintenant="$(date +%s)"
alertes=0
while read -r vmid horodatage; do
  [[ -n "$vmid" ]] || continue
  age=$(( (maintenant - horodatage) / 60 ))
  if (( age > SEUIL_HEURES )); then
    echo "ALERTE : VM $vmid, dernière sauvegarde il y a $age h (seuil : $SEUIL_HEURES h)"
    alertes=$(( alertes + 1 ))
  fi
done
(( alertes == 0 ))
EOF
  chmod +x "$TMP/worktrees/verifier-sauvegardes.sh"
  git -C "$TMP" add worktrees
  git -C "$TMP" "${KARIM[@]}" commit -q -m "feat(supervision): alerte sur l'âge des sauvegardes"
  git -C "$TMP" push -q origin HEAD:main || gl_erreur "push sur main refusé : vérifie la protection de main sur $PROJET (voir l'énoncé)"
fi

# --- Ton clone, en plein travail ---------------------------------------------------------------
mkdir -p "$WB_SRC"
git clone -q "$(gl_url_ssh "$PROJET")" "$CLONE"
cd "$CLONE"
git config user.name >/dev/null || gl_erreur "identité Git absente (voir M01-E03)"
git switch -q -c e18/rapport-capacite
# commits fabriqués dans TON clone : sans signature ni hooks, sans toucher à sa configuration
SANS=(-c commit.gpgsign=false -c core.hooksPath=/dev/null)

cat > worktrees/rapport-capacite.sh <<'EOF'
#!/usr/bin/env bash
# rapport-capacite.sh — mémoire et disque alloués aux VMs du pool lab, par étiquette.
set -euo pipefail
# Lit la sortie JSON de : pvesh get /cluster/resources --type vm --output-format json
jq -r '[.[] | select(.pool == "lab")]
       | group_by(.tags // "sans-etiquette")[]
       | "\(.[0].tags // "sans-etiquette") : \(map(.maxmem) | add / 1073741824 | floor) Gio"'
EOF
chmod +x worktrees/rapport-capacite.sh
git add worktrees/rapport-capacite.sh
git "${SANS[@]}" commit -q -m "feat(capacite): rapport de mémoire allouée par étiquette"

cat > worktrees/capacite.md <<'EOF'
# Rapport de capacité du lab

Budget mémoire de `pve01` : 128 Go, dont environ 24 Go pour le socle (PLAN §3.3).
EOF
git add worktrees/capacite.md
git "${SANS[@]}" commit -q -m "docs(capacite): page de synthèse"

# Travail en cours : une partie indexée, une partie non indexée, un fichier non suivi
cat >> worktrees/capacite.md <<'EOF'

## Synthèse par profil

| Profil | Mémoire prévue |
|---|---|
| Socle | 24 Go |
EOF
git add worktrees/capacite.md
cat >> worktrees/capacite.md <<'EOF'
| infra | 40 Go |
<!-- BROUILLON-E18 : compléter les profils openstack, k8s, plateforme -->
EOF
cat > worktrees/notes-brouillon.md <<'EOF'
Notes non versionnées : comparer avec la sortie de pvesh sur une semaine.
EOF

rm -f "$WB_RESS_ETAT/$WB_EX.env"
gl_etat_ecrire "$WB_EX" "REFLOG_DEPART=$(git reflog show --format=%H HEAD | wc -l)"

gl_msg "Prêt : $CLONE, branche e18/rapport-capacite, travail en cours non commité."
gl_msg "Regarde où tu en es : git -C $CLONE status ; git -C $CLONE log --oneline -3"
