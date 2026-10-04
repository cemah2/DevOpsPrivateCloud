#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E42 : fabrique le dépôt de travail de Lucas Martin (jetons GitLab).
#
# Usage : fabriquer-depot.sh [--force] [DOSSIER]
#   DOSSIER  défaut : ${WB_SRC:-$HOME/src}/labo-e42
#   --force  remplace un dépôt existant (sinon refus)
#
# Produit, sans accès réseau :
#   - DOSSIER-origine.git : dépôt nu « origin » (main publiée) ;
#   - DOSSIER : branche feature/rotation-jetons avec 4 commits jamais poussés, et un stash
#     (notes de conception) posé après le premier d'entre eux. L'arbre de travail est propre.
# Identités et dates fixes : deux fabrications donnent les mêmes empreintes.
set -euo pipefail

force=0
if [[ "${1:-}" == --force ]]; then force=1; shift; fi
dest="${1:-${WB_SRC:-$HOME/src}/labo-e42}"
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

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Lucas Martin" GIT_AUTHOR_EMAIL="lucas.martin@medisphere.internal"
export GIT_COMMITTER_NAME="Lucas Martin" GIT_COMMITTER_EMAIL="lucas.martin@medisphere.internal"
t=1775548800   # 2026-04-07T08:00:00Z
g() { git -c init.defaultBranch=main -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }
commit() {
  t=$((t + 4200))
  GIT_AUTHOR_DATE="@$t +0200" GIT_COMMITTER_DATE="@$t +0200" g commit -q --no-verify -m "$1"
}

g init -q --bare "$origine"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
g init -q "$tmp/init"
cd "$tmp/init"
mkdir -p scripts notes
cat > README.md <<'EOF'
# jetons-forge

Outils de suivi des jetons d'accès de la forge (expiration, rotation).
EOF
cat > notes/idees.md <<'EOF'
# Idées en vrac

- Alerter avant l'expiration des jetons de projet.
EOF
g add -A && commit "chore: initialiser le dépôt des outils de jetons"
cat > scripts/lister-jetons.sh <<'EOF'
#!/usr/bin/env bash
# Liste les jetons de projet d'un projet GitLab (jeton d'administration dans GITLAB_TOKEN).
set -euo pipefail
projet="${1:?usage : lister-jetons.sh <id-projet>}"
curl -sf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://git01.par1.medisphere.internal/api/v4/projects/$projet/access_tokens" \
  | jq -r '.[] | [.id, .name, .expires_at] | @tsv'
EOF
chmod +x scripts/lister-jetons.sh
g add -A && commit "feat(jetons): lister les jetons d'un projet"
g remote add origin "file://$origine"
g push -q origin main

cd "$(dirname "$dest")"
g clone -q "file://$origine" "$dest"
cd "$dest"
g config user.name "Lucas Martin"
g config user.email "lucas.martin@medisphere.internal"
g config commit.gpgsign false
g switch -q -c feature/rotation-jetons

cat > scripts/expirations.sh <<'EOF'
#!/usr/bin/env bash
# Affiche les jetons qui expirent dans moins de N jours (30 par défaut).
set -euo pipefail
jours="${1:-30}"
limite="$(date -d "+$jours days" +%F)"
"$(dirname "$0")/lister-jetons.sh" "${PROJET:?}" | awk -F'\t' -v l="$limite" '$3 != "" && $3 <= l'
EOF
chmod +x scripts/expirations.sh
g add -A && commit "feat(jetons): signaler les jetons qui expirent sous 30 jours"

# Stash : notes de conception mises de côté.
cat >> notes/idees.md <<'EOF'
- Conception retenue : rotation automatique 15 jours avant l'échéance, nouveau jeton
  écrit directement dans la variable CI masquée, ancien jeton révoqué par la rotation.
EOF
GIT_AUTHOR_DATE="@$((t + 900)) +0200" GIT_COMMITTER_DATE="@$((t + 900)) +0200" g stash push -q -m "notes de conception de la rotation"

cat > scripts/rotation.sh <<'EOF'
#!/usr/bin/env bash
# Renouvelle un jeton de projet (rotation) et affiche le nouveau jeton une seule fois.
set -euo pipefail
projet="${1:?}" jeton="${2:?}"
curl -sf -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://git01.par1.medisphere.internal/api/v4/projects/$projet/access_tokens/$jeton/rotate" \
  | jq -r '.token'
EOF
chmod +x scripts/rotation.sh
g add -A && commit "feat(jetons): renouveler un jeton de projet par l'API"

cat >> scripts/rotation.sh <<'EOF'
# Rappel : mettre à jour la variable CI qui contient le jeton juste après la rotation.
EOF
g add -A && commit "docs(jetons): rappeler la mise à jour de la variable CI après rotation"

cat > scripts/rapport.sh <<'EOF'
#!/usr/bin/env bash
# Rapport hebdomadaire des expirations, au format Markdown, pour le canal #plateforme.
set -euo pipefail
echo "| Projet | Jeton | Expire le |"
echo "|---|---|---|"
"$(dirname "$0")/expirations.sh" 45 | awk -F'\t' '{print "| " ENVIRON["PROJET"] " | " $2 " | " $3 " |"}'
EOF
chmod +x scripts/rapport.sh
g add -A && commit "feat(jetons): produire le rapport hebdomadaire des expirations"


echo "Dépôt fabriqué : $dest (origine : $origine)"
