#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E17 : crée formation/labo-fuite, un dépôt où un secret a été poussé.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E17/fabriquer-depot.sh
#
# Effets (une seule fois ; le script refuse de tourner si le projet existe) :
#   - projet privé formation/labo-fuite, julien.petit y est Developer ;
#   - un VRAI jeton d'accès de projet (« collecte-medisphere », Reporter, read_repository,
#     7 jours, limité à ce projet) est créé, puis écrit par « Julien » dans config/collecte.env ;
#   - historique : 5 commits sur main, l'étiquette v0.1.0, la branche feat/export-csv
#     et une merge request ouverte par Julien depuis cette branche ;
#   - ~/.local/state/workbook/ressources/M01-E17.env : identifiants (non secrets) pour le check.
# Le jeton ne donne accès qu'à ce projet de bac à sable et expire seul sous 7 jours.
set -euo pipefail

WB_EX="M01-E17"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"
trap gl_rendre_jetons EXIT

GROUPE="formation"
PROJET="$GROUPE/labo-fuite"
JULIEN=(-c "user.name=Julien Petit" -c "user.email=julien.petit@medisphere.internal")

[[ $# -eq 0 ]] || { echo "Usage : $0" >&2; exit 2; }
gl_prerequis_api git
[[ -z "$(gl_id_projet "$PROJET")" ]] \
  || gl_erreur "$PROJET existe déjà. Pour recommencer, supprime-le (Paramètres > Général > Avancé) ou renomme-le, puis relance."

gid="$(gl_api GET "groups/$GROUPE" | jq -r .id)"
pid="$(gl_api_json POST projects "$(jq -nc --argjson ns "$gid" \
  '{name:"labo-fuite", path:"labo-fuite", namespace_id:$ns, visibility:"private",
    description:"Atelier M01-E17 : fuite de secret (bac à sable)"}')" | jq -r .id)"
uid_julien="$(gl_id_utilisateur julien.petit)"
gl_api_json POST "projects/$pid/members" "$(jq -nc --argjson u "$uid_julien" '{user_id:$u, access_level:30}')" >/dev/null

rep="$(gl_api_json POST "projects/$pid/access_tokens" "$(jq -nc --arg e "$(date -d '+7 days' +%F)" \
  '{name:"collecte-medisphere", scopes:["read_repository"], access_level:20, expires_at:$e}')")"
tid="$(jq -r .id <<<"$rep")"
rm -f "$WB_RESS_ETAT/$WB_EX.env"
gl_etat_ecrire "$WB_EX" "PROJET_ID=$pid"
gl_etat_ecrire "$WB_EX" "JETON_ID=$tid"

# --- Historique de Julien (dossier temporaire, poussé avec ta clé SSH) ---------------------------
tmp="$(mktemp -d)"
trap 'gl_rendre_jetons; rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b main depot && cd depot
gl_git_neutre .
g() { git "${JULIEN[@]}" "$@"; }

cat > README.md <<'EOF'
# Collecte MédiSphère

Collecte nocturne des métadonnées des dépôts de la forge (taille, dernière activité),
pour le tableau de bord de l'équipe Plateforme.
EOF
g add README.md && g commit -q -m "chore: initialisation du projet"

mkdir -p scripts
cat > scripts/collecte.sh <<'EOF'
#!/usr/bin/env bash
# collecte.sh — interroge l'API GitLab et enregistre les métadonnées des projets.
set -euo pipefail
source "$(dirname "$0")/../config/collecte.env"
curl -sf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects?per_page=100" \
  | jq -r '.[] | [.path_with_namespace, .last_activity_at] | @tsv'
EOF
chmod +x scripts/collecte.sh
g add scripts && g commit -q -m "feat: script de collecte"

mkdir -p config
{
  echo "# Configuration de la collecte"
  echo "GITLAB_URL=$WB_GITLAB_URL"
  echo "GITLAB_TOKEN=$(jq -r .token <<<"$rep")"
  echo "DB_HOST=10.10.20.50"
  echo "DB_PASSWORD=Collecte-2026!"
} > config/collecte.env
g add config && g commit -q -m "feat: configuration de la collecte"

sed -i 's/per_page=100"/per_page=100\&archived=false"/' scripts/collecte.sh
g commit -q -am "fix: ignorer les projets archivés"
g tag -a v0.1.0 -m "v0.1.0"

g switch -q -c feat/export-csv
cat >> scripts/collecte.sh <<'EOF'
# Export CSV (à finaliser)
EOF
g commit -q -am "feat: début de l'export CSV"

g switch -q main
g rm -q config/collecte.env
g commit -q -m "chore: retrait du fichier de configuration"

git remote add origin "$(gl_url_ssh "$PROJET")"
git push -q origin main feat/export-csv v0.1.0 || gl_erreur "push SSH vers $PROJET impossible"

gl_emprunter julien.petit JETON_JULIEN
gl_api_jeton "$JETON_JULIEN" POST "projects/$pid/merge_requests" "$(jq -nc \
  '{source_branch:"feat/export-csv", target_branch:"main", title:"feat: export CSV de la collecte",
    description:"Première version de l'"'"'export, à relire."}')" >/dev/null

gl_msg "Prêt : $PROJET créé. Le ticket SEC-227 de l'énoncé t'attend."
