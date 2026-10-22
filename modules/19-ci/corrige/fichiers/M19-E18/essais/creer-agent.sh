#!/usr/bin/env bash
# creer-agent.sh — M19-E18 (PLAT-2018), sur adm01 : ~/m19/e18/creer-agent.sh
# Enregistre l'agent « k8s-par1 » dans plateforme/k8s et crée son jeton, envoyé DIRECTEMENT dans le
# Vault « critique » (secrets/gitlab-agent.yml) sans fichier en clair ni affichage.
# Prérequis : .gitlab/agents/k8s-par1/config.yaml fusionné sur main de plateforme/k8s (le nom de
# l'agent doit correspondre au dossier) ; jeton d'administration personnel (portée api, J+1) dans
# ~/.config/workbook/gitlab-api-ecriture.token (600) ; clone ~/src/k8s, ~/src/ansible (ansible-vault).
set -euo pipefail

GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
JETON_ADMIN="${GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-api-ecriture.token}"
PROJET="plateforme%2Fk8s"
K8S="${MS_K8S_DIR:-$HOME/src/k8s}"
ANSIBLE="${MS_ANSIBLE_DIR:-$HOME/src/ansible}"
CIBLE="$K8S/secrets/gitlab-agent.yml"

[[ -r "$JETON_ADMIN" && "$(stat -c %a "$JETON_ADMIN")" == 600 ]] || { echo "jeton d'administration absent ou pas en 600" >&2; exit 2; }
[[ ! -e "$CIBLE" ]] || { echo "$CIBLE existe déjà : utilise ansible-vault edit (rotation), pas ce script" >&2; exit 2; }
api() { curl -sSf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_ADMIN")") "$@"; }

id_agent="$(api "$GITLAB/projects/$PROJET/cluster_agents" | jq -r '.[] | select(.name == "k8s-par1") | .id')"
if [[ -z "$id_agent" ]]; then
  id_agent="$(api -X POST "$GITLAB/projects/$PROJET/cluster_agents" --data name=k8s-par1 | jq -r .id)"
  echo "agent k8s-par1 enregistré (id $id_agent)"
else
  echo "agent k8s-par1 déjà enregistré (id $id_agent)"
fi

# Le jeton n'est rendu qu'une fois : du JSON de la réponse directement vers ansible-vault (entrée standard).
api -X POST "$GITLAB/projects/$PROJET/cluster_agents/$id_agent/tokens" \
    --data "name=k8s-par1-$(date +%Y%m%d)" --data-urlencode "description=agentk de k8s-par1 (M19-E18)" \
  | jq -r '"gitlab_agent_jeton: \"" + .token + "\""' \
  | (cd "$ANSIBLE" && uv run ansible-vault encrypt --encrypt-vault-id critique --output "$CIBLE" -)
head -n 1 "$CIBLE"
echo "jeton rangé dans $CIBLE ; suite : cd $K8S && outils/secrets-k8s.sh appliquer gitlab-agent"
