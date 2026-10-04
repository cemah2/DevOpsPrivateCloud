#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E41 : fabrique le dépôt de travail de Lucas Martin.
#
# Usage : fabriquer-depot.sh [--force] [DOSSIER]
#   DOSSIER  défaut : ${WB_SRC:-$HOME/src}/labo-e41
#   --force  remplace un dépôt existant (sinon refus)
#
# Produit, sans aucun accès réseau :
#   - DOSSIER-origine.git : dépôt nu qui joue le rôle du serveur (« origin ») ;
#   - DOSSIER             : clone de travail avec, sur la branche feature/sauvegarde-gitlab,
#                           3 commits jamais poussés, 1 stash et une modification non commitée.
# Les identités et les dates sont fixes : deux fabrications donnent les mêmes empreintes.
# Le script est lancé par la panne M01-E41 ; tu peux aussi le lancer toi-même pour t'entraîner.
set -euo pipefail

force=0
if [[ "${1:-}" == --force ]]; then force=1; shift; fi
dest="${1:-${WB_SRC:-$HOME/src}/labo-e41}"
origine="$dest-origine.git"

if [[ -e "$dest" || -e "$origine" ]]; then
  if ((force)); then
    rm -rf "$dest" "$origine"
  else
    echo "Refus : $dest ou $origine existe déjà (--force pour remplacer)." >&2
    exit 1
  fi
fi
mkdir -p "$(dirname "$dest")"

# Isolement de la configuration de l'apprenant : pas de signature, pas de hooks, pas de modèle.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Lucas Martin" GIT_AUTHOR_EMAIL="lucas.martin@medisphere.internal"
export GIT_COMMITTER_NAME="Lucas Martin" GIT_COMMITTER_EMAIL="lucas.martin@medisphere.internal"
t=1775030400   # 2026-04-01T08:00:00Z
g() { git -c init.defaultBranch=main -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }
commit() {
  t=$((t + 5400))
  GIT_AUTHOR_DATE="@$t +0200" GIT_COMMITTER_DATE="@$t +0200" g commit -q --no-verify -m "$1"
}

# --- Dépôt « serveur » et historique publié -----------------------------------------
g init -q --bare "$origine"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
g init -q "$tmp/init"
cd "$tmp/init"
cat > README.md <<'EOF'
# outils-forge

Scripts d'exploitation de la forge GitLab de MédiSphère (git01).

- `scripts/` : scripts d'exploitation ;
- `docs/` : runbooks associés.
EOF
cat > .gitignore <<'EOF'
*.tar
*.log
EOF
g add -A && commit "chore: initialiser le dépôt des outils de la forge"
mkdir -p scripts docs
cat > scripts/verifier-sante.sh <<'EOF'
#!/usr/bin/env bash
# Vérifie les sondes de santé de GitLab depuis git01 (liste blanche de supervision).
set -euo pipefail
for sonde in readiness liveness; do
  curl -sf "http://127.0.0.1/-/$sonde" >/dev/null && echo "$sonde : OK" || echo "$sonde : KO"
done
EOF
chmod +x scripts/verifier-sante.sh
g add -A && commit "feat(sante): ajouter la vérification des sondes de santé"
cat > docs/README.md <<'EOF'
# Runbooks de la forge

Chaque runbook suit le modèle de l'équipe : déclencheur, prérequis, étapes, vérification,
retour arrière, escalade.
EOF
g add -A && commit "docs: ajouter l'index des runbooks"
g remote add origin "file://$origine"
g push -q origin main

# --- Clone de travail (par le protocole file:// : objets empaquetés, pas de liens durs) ----
cd "$(dirname "$dest")"
g clone -q "file://$origine" "$dest"
cd "$dest"
g config user.name "Lucas Martin"
g config user.email "lucas.martin@medisphere.internal"
g config commit.gpgsign false
g switch -q -c feature/sauvegarde-gitlab

cat > scripts/sauvegarde-gitlab.sh <<'EOF'
#!/usr/bin/env bash
# Sauvegarde complète de GitLab : données (gitlab-backup) et configuration (backup-etc).
set -euo pipefail
gitlab-backup create STRATEGY=copy
gitlab-ctl backup-etc --backup-path /var/opt/gitlab/backups/config
EOF
chmod +x scripts/sauvegarde-gitlab.sh
g add -A && commit "feat(sauvegarde): ajouter le script de sauvegarde de GitLab"

cat > scripts/sauvegarde-gitlab.sh <<'EOF'
#!/usr/bin/env bash
# Sauvegarde complète de GitLab : données (gitlab-backup) et configuration (backup-etc),
# puis copie hors de la VM vers PBS (espace de noms par1/git01).
set -euo pipefail
gitlab-backup create STRATEGY=copy
gitlab-ctl backup-etc --backup-path /var/opt/gitlab/backups/config
# Copie vers PBS : la variable PBS_REPOSITORY et le secret sont fournis par l'environnement.
proxmox-backup-client backup gitlab.pxar:/var/opt/gitlab/backups --ns par1/git01
EOF
cat > docs/RB-010-restaurer-gitlab.md <<'EOF'
# RB-010 — Restaurer GitLab

Déclencheur : perte de git01 ou corruption des données de GitLab.

1. Recréer une VM avec la même version de GitLab que la sauvegarde.
2. Restaurer /etc/gitlab (gitlab.rb et gitlab-secrets.json).
3. Restaurer les données avec gitlab-backup restore.
EOF
g add -A && commit "feat(sauvegarde): copier la sauvegarde vers PBS"

cat >> docs/RB-010-restaurer-gitlab.md <<'EOF'

Point d'attention : sans gitlab-secrets.json, les secrets chiffrés en base (variables CI,
jetons des runners, secrets 2FA) sont perdus, même si la restauration des données réussit.
EOF
g add -A && commit "docs(runbook): détailler la restauration de gitlab-secrets.json"

# Stash : essai d'une option de simulation, mis de côté.
# shellcheck disable=SC2016  # texte inséré tel quel dans le script fabriqué
sed -i 's/^set -euo pipefail$/set -euo pipefail\nSIMULATION="${SIMULATION:-0}"   # essai : option --dry-run/' scripts/sauvegarde-gitlab.sh
GIT_AUTHOR_DATE="@$((t + 600)) +0200" GIT_COMMITTER_DATE="@$((t + 600)) +0200" g stash push -q -m "essai option --dry-run"

# Modification en cours, non commitée.
cat >> docs/RB-010-restaurer-gitlab.md <<'EOF'
4. Vérifier : gitlab-rake gitlab:check SANITIZE=true et gitlab-rake gitlab:doctor:secrets.
EOF

echo "Dépôt fabriqué : $dest (origine : $origine)"
