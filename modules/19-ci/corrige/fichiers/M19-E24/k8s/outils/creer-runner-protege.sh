#!/usr/bin/env bash
# plateforme/k8s — outils/creer-runner-protege.sh (M19-E24, SEC-2024).
# Crée le runner d'instance « k8s-par1-protege » par l'API de GitLab (POST /user/runners) et range
# son jeton glrt- dans secrets/gitlab-runner-protege.yml, chiffré par Ansible Vault (identité
# critique), SANS que le jeton ne passe jamais par un fichier en clair, un argument de commande ou
# le terminal.
#
# Usage (depuis la racine du clone ~/src/k8s, sur adm01) :
#   outils/creer-runner-protege.sh
# Prérequis : jeton personnel d'administration à durée courte (portées api + admin_mode) dans
#   ~/.config/workbook/gitlab-admin.token (M01) ; ansible-vault par l'environnement uv de
#   ~/src/ansible ; jq.
# Idempotence : refuse de créer un second runner du même nom (un runner existant se gère par
# PUT /runners/:id, ou se supprime d'abord, sciemment).
set -euo pipefail

GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_ADMIN="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
ANSIBLE_DIR="${ANSIBLE_DIR:-$HOME/src/ansible}"
NOM="k8s-par1-protege"
SORTIE="secrets/gitlab-runner-protege.yml"

[[ -r "$JETON_ADMIN" ]] || { echo "jeton d'administration illisible : $JETON_ADMIN" >&2; exit 1; }
[[ -d secrets ]] || { echo "à lancer depuis la racine du dépôt plateforme/k8s" >&2; exit 1; }
[[ ! -e "$SORTIE" ]] || { echo "$SORTIE existe déjà : runner déjà créé ?" >&2; exit 1; }

# En-tête d'authentification passé à curl par un fichier de configuration lu sur un descripteur
# (jamais en argument : visible par ps).
api() {
  local methode="$1" chemin="$2"
  shift 2
  curl -sSf --max-time 20 -X "$methode" \
    -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"$JETON_ADMIN")") \
    "$GITLAB_URL/api/v4/$chemin" "$@"
}

existants="$(api GET "runners/all?type=instance_type&per_page=100" \
  | jq -r --arg n "$NOM" '[.[] | select(.description == $n)] | length')"
if (( existants > 0 )); then
  echo "un runner « $NOM » existe déjà ($existants) : rien n'est créé" >&2
  exit 1
fi

# Création : instance, ref_protected, étiquette protege, pas de jobs sans étiquette, 1 h au plus.
reponse="$(api POST user/runners \
  --data-urlencode "runner_type=instance_type" \
  --data-urlencode "description=$NOM" \
  --data-urlencode "access_level=ref_protected" \
  --data-urlencode "tag_list=protege" \
  --data-urlencode "run_untagged=false" \
  --data-urlencode "maximum_timeout=3600" \
  --data-urlencode "maintenance_note=SEC-2024 : signature et promotion ; jobs dans ci-jobs-protege")"

id="$(jq -r '.id' <<<"$reponse")"
echo "runner $NOM créé (id $id)"

# Le jeton ne quitte la réponse que vers ansible-vault (entrée standard), jamais vers le terminal.
umask 077
jq -r '"espace: gitlab-runner\nsecret: gitlab-runner-protege-jeton\ndonnees:\n  runner-token: \"" + .token + "\"\n  runner-registration-token: \"\""' <<<"$reponse" \
  | uv run --project "$ANSIBLE_DIR" ansible-vault encrypt \
      --vault-id "critique@$ANSIBLE_DIR/outils/vault-pass-client.sh" \
      --output "$SORTIE"
unset reponse
echo "jeton chiffré dans $SORTIE (à committer, puis : outils/secrets-k8s.sh gitlab-runner-protege)"
echo "inscris le runner $NOM (id $id) au registre des secrets."
