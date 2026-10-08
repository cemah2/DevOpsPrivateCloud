#!/usr/bin/env bash
# deployer.sh — M10-E46 : seul chemin de déploiement de plateforme/openstack, depuis adm01.
# Refuse de déployer autre chose que le commit de origin/main, propre et validé par la CI ; trace
# le déploiement par une étiquette deploye-AAAAMMJJ-HHMM poussée sur le dépôt.
#
# Usage : outils/deployer.sh ACTION [OPTIONS KOLLA…]   ex. : outils/deployer.sh deploy
#         outils/deployer.sh reconfigure -t keystone
# Prérequis : identité Vault critique (ansible.cfg du projet, M10-E03), jeton GitLab des checks en lecture
# (~/.config/workbook/gitlab-checks.token) pour vérifier le pipeline.
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage : $0 ACTION [OPTIONS KOLLA…]" >&2; exit 2; }
action="$1"; shift
racine="$(git rev-parse --show-toplevel)"
cd "$racine"

git fetch --quiet origin main
[[ -z "$(git status --porcelain)" ]] || { echo "copie de travail modifiée : refus" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "HEAD n'est pas origin/main : refus" >&2; exit 1; }

jeton="$HOME/.config/workbook/gitlab-checks.token"
statut="$(curl -sf -H "PRIVATE-TOKEN: $(<"$jeton")" \
  "https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Fopenstack/pipelines?sha=$(git rev-parse HEAD)&per_page=1" \
  | jq -r '.[0].status // "aucun"')"
[[ "$statut" == success ]] || { echo "pipeline du commit : $statut (attendu success) : refus" >&2; exit 1; }

uv sync --frozen
echo "déploiement de $(git rev-parse --short HEAD) : kolla-ansible $action $*"
uv run kolla-ansible "$action" -i inventaire/multinode --configdir etc/kolla "$@"

if [[ "$action" =~ ^(deploy|reconfigure|upgrade|deploy-containers)$ ]]; then
  etiquette="deploye-$(date +%Y%m%d-%H%M)"
  git tag -a "$etiquette" -m "kolla-ansible $action $* — $(whoami)@$(hostname -s)"
  git push --quiet origin "$etiquette"
  echo "étiquette $etiquette poussée"
fi
