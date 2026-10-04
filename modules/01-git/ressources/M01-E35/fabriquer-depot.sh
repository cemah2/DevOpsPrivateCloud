#!/usr/bin/env bash
# =============================================================================
# fabriquer-depot.sh — prépare l'épreuve chronométrée M01-E35 (workflow complet)
#
# Usage (sur adm01, depuis le clone du workbook) :
#   modules/01-git/ressources/M01-E35/fabriquer-depot.sh
#
# Crée un projet NEUF formation/chrono-<AAAAMMJJ-HHMM> (jamais de suppression :
# relancer le script crée un autre projet), avec :
#   - un historique sur main écrit par Karim Benali, étiqueté v1.0.0, puis un correctif ;
#   - la branche feature/rappel-sms de Julien Petit, telle qu'il l'a laissée ;
#   - une MR ouverte par Karim pour Julien, et un commentaire de revue de Karim ;
#   - les règles de la plateforme : main protégée, pipeline et discussions résolues
#     obligatoires, étiquettes v* protégées, CI par les gabarits de ci-templates (v1).
#
# Les commits « au nom » des personnages passent par des jetons d'emprunt
# d'identité (impersonation tokens) créés avec ton jeton d'administration, valables
# un jour et révoqués à la fin du script.
#
# Prérequis : jq, curl, git, openssl ; jeton d'administration (api, + admin_mode si
# Admin Mode est actif) dans WB_GITLAB_ADMIN_TOKEN_FILE ; comptes karim.benali et
# julien.petit (M01-E05) ; plateforme/ci-templates avec la branche v1 (M01-E24/E25).
# Variables facultatives : WB_MERGE_METHOD (rebase_merge par défaut, ou ff, ou
# merge) — reprends la méthode choisie pour la plateforme en M01-E11.
# =============================================================================
# shellcheck disable=SC2016  # contenus de fichiers et motifs sed écrits littéralement
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RACINE="$(cd "$ICI/../../../.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$RACINE/lab/lab.env" ]] && source "$RACINE/lab/lab.env"

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
HOTE="${URL#https://}"
JETON_ADMIN_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
METHODE="${WB_MERGE_METHOD:-rebase_merge}"
ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M01-E35"

for outil in jq curl git openssl; do
  command -v "$outil" >/dev/null || { echo "Outil manquant : $outil" >&2; exit 2; }
done
[[ -r "$JETON_ADMIN_FICHIER" ]] || { echo "Jeton d'administration illisible : $JETON_ADMIN_FICHIER" >&2; exit 2; }
case "$METHODE" in rebase_merge|ff|merge) ;; *) echo "WB_MERGE_METHOD invalide : $METHODE" >&2; exit 2 ;; esac

TMP="$(mktemp -d)"
JETONS_A_REVOQUER=()
nettoyer() {
  local e uid jid
  for e in "${JETONS_A_REVOQUER[@]}"; do
    uid="${e%%:*}"; jid="${e#*:}"
    curl -s -o /dev/null -X DELETE -H "PRIVATE-TOKEN: $(<"$JETON_ADMIN_FICHIER")" \
      "$URL/api/v4/users/$uid/impersonation_tokens/$jid" || true
  done
  rm -rf "$TMP"
}
trap nettoyer EXIT

# api [-j JETON] MÉTHODE CHEMIN [arguments curl…] — appel de l'API REST v4
api() {
  local jeton
  jeton="$(<"$JETON_ADMIN_FICHIER")"
  if [[ "$1" == -j ]]; then jeton="$2"; shift 2; fi
  local m="$1" p="$2"; shift 2
  curl -sS --fail-with-body --max-time 30 -X "$m" -H "PRIVATE-TOKEN: $jeton" "$@" "$URL/api/v4/$p"
}

echo "== Vérifications"
moi="$(api GET user)" || { echo "Jeton d'administration refusé." >&2; exit 1; }
[[ "$(jq -r .is_admin <<<"$moi")" == true ]] || { echo "Le jeton n'est pas celui d'un administrateur." >&2; exit 1; }
FORMATION_ID="$(api GET namespaces/formation | jq -r .id)"
api GET "projects/plateforme%2Fci-templates/repository/branches/v1" >/dev/null \
  || { echo "Branche v1 de plateforme/ci-templates introuvable (M01-E24/E25)." >&2; exit 1; }
id_de() { api GET "users?username=$1" | jq -r '.[0].id // empty'; }
KARIM_ID="$(id_de karim.benali)"; JULIEN_ID="$(id_de julien.petit)"
[[ -n "$KARIM_ID" && -n "$JULIEN_ID" ]] || { echo "Comptes karim.benali / julien.petit introuvables (M01-E05)." >&2; exit 1; }

echo "== Jetons d'emprunt d'identité (valables jusqu'à demain, révoqués en fin de script)"
jeton_pour() {   # jeton_pour UID → affiche le jeton, mémorise son id pour révocation
  local r
  r="$(api POST "users/$1/impersonation_tokens" \
        --data-urlencode "name=chrono-e35-$(date +%s)" \
        --data-urlencode "scopes[]=api" --data-urlencode "scopes[]=write_repository" \
        --data-urlencode "expires_at=$(date -d tomorrow +%F)")" \
    || { echo "Création du jeton d'emprunt refusée (portée admin_mode du jeton d'administration ?)" >&2; return 1; }
  JETONS_A_REVOQUER+=("$1:$(jq -r .id <<<"$r")")
  jq -r .token <<<"$r"
}
KARIM_JETON="$(jeton_pour "$KARIM_ID")"
JULIEN_JETON="$(jeton_pour "$JULIEN_ID")"

echo "== Projet"
NOM="chrono-$(date +%Y%m%d-%H%M)"
projet="$(api POST projects --data-urlencode "name=$NOM" --data-urlencode "path=$NOM" \
  --data-urlencode "namespace_id=$FORMATION_ID" --data-urlencode "visibility=private" \
  --data-urlencode "default_branch=main" \
  --data-urlencode "description=Épreuve chronométrée M01-E35 : rappels de rendez-vous par SMS")"
PID="$(jq -r .id <<<"$projet")"
CHEMIN="$(jq -r .path_with_namespace <<<"$projet")"
api POST "projects/$PID/members" --data-urlencode "user_id=$KARIM_ID" --data-urlencode "access_level=40" >/dev/null
api POST "projects/$PID/members" --data-urlencode "user_id=$JULIEN_ID" --data-urlencode "access_level=30" >/dev/null
echo "Projet $CHEMIN (id $PID)"

echo "== Historique"
cat > "$TMP/askpass" <<'EOF'
#!/bin/sh
printf '%s\n' "$WB_MDP"
EOF
chmod 700 "$TMP/askpass"
G=(git -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main)
DEPOT="$TMP/depot"
"${G[@]}" init -q "$DEPOT"
cd "$DEPOT"
commit_de() {   # commit_de karim|julien "message" [date]
  local nom email
  case "$1" in
    karim)  nom="Karim Benali"; email="karim.benali@medisphere.internal" ;;
    julien) nom="Julien Petit"; email="julien.petit@medisphere.internal" ;;
  esac
  git add -A
  GIT_AUTHOR_NAME="$nom" GIT_AUTHOR_EMAIL="$email" GIT_COMMITTER_NAME="$nom" GIT_COMMITTER_EMAIL="$email" \
    "${G[@]}" commit -q -m "$2"
}
pousser() {   # pousser karim|julien REFSPEC…
  local qui="$1" jeton user; shift
  if [[ "$qui" == karim ]]; then jeton="$KARIM_JETON"; user=karim.benali; else jeton="$JULIEN_JETON"; user=julien.petit; fi
  WB_MDP="$jeton" GIT_ASKPASS="$TMP/askpass" GIT_TERMINAL_PROMPT=0 \
    "${G[@]}" -c credential.helper= push -q -o ci.skip "https://${user}@${HOTE}/${CHEMIN}.git" "$@"
}

# --- main : initialisation (Karim) ---
cat > README.md <<'EOF'
# Rappels de rendez-vous (démonstrateur MédiAgenda)

`rappel.sh` calcule l'heure d'envoi du rappel d'un rendez-vous (24 h avant par défaut).

- Tests : `bash tests/test_rappel.sh`
- Contribution : branche, MR, Conventional Commits ; versions publiées par semantic-release.
EOF
cat > .gitlab-ci.yml <<'EOF'
include:
  - project: plateforme/ci-templates
    ref: v1
    file:
      - templates/qualite.yml
      - templates/release.yml

tests:
  stage: test
  tags: [shell]
  script:
    - bash tests/test_rappel.sh
EOF
cat > commitlint.config.mjs <<'EOF'
export default { extends: ['@commitlint/config-conventional'] };
EOF
cat > .releaserc.json <<'EOF'
{
  "branches": ["main"],
  "tagFormat": "v${version}",
  "plugins": [
    ["@semantic-release/commit-analyzer", { "preset": "conventionalcommits" }],
    ["@semantic-release/release-notes-generator", { "preset": "conventionalcommits" }],
    "@semantic-release/gitlab"
  ]
}
EOF
commit_de karim "chore: initialise le projet des rappels"

mkdir -p tests
cat > rappel.sh <<'EOF'
#!/usr/bin/env bash
# rappel.sh — heure d'envoi du rappel d'un rendez-vous (démonstrateur MédiAgenda)
set -euo pipefail

DELAI_HEURES="${DELAI_HEURES:-24}"

# heure_rappel "AAAA-MM-JJ HH:MM" → heure d'envoi du rappel
heure_rappel() {
  date -d "$1 $DELAI_HEURES hours ago" '+%Y-%m-%d %H:%M'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  heure_rappel "${1:?Usage : rappel.sh \"AAAA-MM-JJ HH:MM\"}"
fi
EOF
cat > tests/test_rappel.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../rappel.sh
source "$(dirname "$0")/../rappel.sh"
attendu="2026-10-09 10:00"
obtenu="$(heure_rappel "2026-10-10 10:00")"
[[ "$obtenu" == "$attendu" ]] || { echo "ÉCHEC : attendu $attendu, obtenu $obtenu"; exit 1; }
echo "OK : heure_rappel"
EOF
commit_de karim "feat: calcule l'heure d'envoi des rappels"
"${G[@]}" tag v1.0.0
BASE_V1="$(git rev-parse HEAD)"

# --- branche de Julien (partie de v1.0.0) ---
git checkout -q -b feature/rappel-sms
SECRET="glpat-$(openssl rand -hex 10)"
mkdir -p config
printf 'MEDISMS_API_TOKEN="%s"\n' "$SECRET" > config/medisms.env
cat > rappel.sh <<'EOF'
#!/usr/bin/env bash
# rappel.sh — heure d'envoi du rappel d'un rendez-vous (démonstrateur MédiAgenda)
set -euo pipefail

DELAI_HEURES="${DELAI_HEURES:-24}"
MEDISMS_URL="https://api.medisms.example/v1/sms"

# heure_rappel "AAAA-MM-JJ HH:MM" → heure d'envoi du rappel (format ISO 8601)
heure_rappel() {
  date -d "$1 $DELAI_HEURES hours ago" '+%Y-%m-%dT%H:%M'
}

# envoyer_sms NUMÉRO MESSAGE
envoyer_sms() {
  source "$(dirname "${BASH_SOURCE[0]}")/config/medisms.env"
  curl -sf -H "Authorization: Bearer $MEDISMS_API_TOKEN" --data-urlencode "to=$1" --data-urlencode "text=$2" "$MEDISMS_URL"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  heure_rappel "${1:?Usage : rappel.sh \"AAAA-MM-JJ HH:MM\"}"
fi
EOF
commit_de julien "WIP sms"
sed -i 's/^# envoyer_sms NUMÉRO MESSAGE$/# envoyer_sms NUMÉRO MESSAGE — envoie un SMS par la passerelle MédiSMS/' rappel.sh
commit_de julien "fix typo"
sed -i 's/^attendu="2026-10-09 10:00"$/attendu="2026-10-09T10:00"/' tests/test_rappel.sh
commit_de julien "feat(sms): envoie les rappels par SMS"
git rm -q config/medisms.env
printf 'config/*.env\n' > .gitignore
sed -i 's|^  source "$(dirname "${BASH_SOURCE\[0\]}")/config/medisms.env"$|  : "${MEDISMS_API_TOKEN:?variable MEDISMS_API_TOKEN absente}"|' rappel.sh
commit_de julien "retire le jeton du dépôt"
printf '\n## SMS\n\n`envoyer_sms` lit le jeton de la passerelle dans `MEDISMS_API_TOKEN` (jamais dans le dépôt).\n' >> README.md
commit_de julien "fixup! feat(sms): envoie les rappels par SMS"

# --- main avance pendant ce temps (Karim) ---
git checkout -q main
sed -i "s|^  date -d \"\$1 \$DELAI_HEURES hours ago\" '+%Y-%m-%d %H:%M'\$|  TZ=Europe/Paris date -d \"\$1 \$DELAI_HEURES hours ago\" '+%Y-%m-%d %H:%M'|" rappel.sh
grep -q 'TZ=Europe/Paris' rappel.sh || { echo "Fabrication : correctif de Karim non appliqué" >&2; exit 1; }
commit_de karim "fix: calcule l'heure du rappel dans le fuseau de Paris"

pousser karim main
pousser karim v1.0.0
pousser julien feature/rappel-sms

echo "== Règles du projet"
api PUT "projects/$PID" \
  --data-urlencode "merge_method=$METHODE" \
  --data-urlencode "only_allow_merge_if_pipeline_succeeds=true" \
  --data-urlencode "allow_merge_on_skipped_pipeline=false" \
  --data-urlencode "only_allow_merge_if_all_discussions_are_resolved=true" \
  --data-urlencode "remove_source_branch_after_merge=true" >/dev/null
api DELETE "projects/$PID/protected_branches/main" >/dev/null 2>&1 || true
api POST "projects/$PID/protected_branches" --data-urlencode "name=main" \
  --data-urlencode "push_access_level=0" --data-urlencode "merge_access_level=40" \
  --data-urlencode "allow_force_push=false" >/dev/null
api POST "projects/$PID/protected_tags" --data-urlencode "name=v*" --data-urlencode "create_access_level=40" >/dev/null

echo "== Ticket, MR et revue"
ISSUE="$(api -j "$JULIEN_JETON" POST "projects/$PID/issues" \
  --data-urlencode "title=Envoyer les rappels de rendez-vous par SMS" \
  --data-urlencode "description=Les patients oublient leurs rendez-vous : on veut un SMS de rappel la veille. La passerelle MédiSMS est prête, j'ai commencé dans feature/rappel-sms. — Julien" \
  | jq -r .iid)"
MR="$(api -j "$KARIM_JETON" POST "projects/$PID/merge_requests" \
  --data-urlencode "source_branch=feature/rappel-sms" --data-urlencode "target_branch=main" \
  --data-urlencode "title=Draft: feat(sms): rappels de rendez-vous par SMS" \
  --data-urlencode "description=Julien est en congé : j'ouvre la MR pour lui. À reprendre et livrer (v1.1.0). Closes #$ISSUE" )"
MR_IID="$(jq -r .iid <<<"$MR")"
MR_URL="$(jq -r .web_url <<<"$MR")"
api -j "$KARIM_JETON" POST "projects/$PID/merge_requests/$MR_IID/discussions" \
  --data-urlencode "body=Deux points avant fusion : (1) MEDISMS_URL doit pouvoir être surchargée par l'environnement (valeur par défaut gardée), comme toutes nos variables de configuration ; (2) je vois passer un jeton MédiSMS dans l'historique de la branche : il ne doit pas arriver sur la forge, même dans un commit intermédiaire." >/dev/null

mkdir -p "$ETAT"
printf '%s\n' "$CHEMIN" > "$ETAT/projet"
date -Is > "$ETAT/debut"
: "$BASE_V1"

cat <<EOF

Projet prêt : $URL/$CHEMIN
MR à livrer : $MR_URL
(Le jeton MédiSMS de la branche est factice ; il est quand même à traiter comme un vrai.)

Le chrono démarre maintenant ($(date +%H:%M)). Consignes : modules/01-git/enonce/03-production.md, M01-E35.
Vérification à la fin : lab/bin/check 01 35
EOF
