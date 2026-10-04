#!/usr/bin/env bash
# installer-gitlab.sh — installe GitLab CE en version choisie sur git01 (M01-E04).
# À lancer SUR git01, en root, APRÈS preparer-git01.sh et après avoir déposé
# /etc/gitlab/gitlab.rb (root, 600).
# Usage : installer-gitlab.sh <VERSION>      ex. installer-gitlab.sh 19.3.2-ce.0
#         (liste des versions : apt-cache madison gitlab-ce)
set -euo pipefail
VERSION="${1:?Usage : $0 <VERSION> (ex. 19.3.2-ce.0)}"
[[ "$VERSION" == 19.3.* ]] || { echo "Refus : M01-E04 installe une 19.3.x (reçu : $VERSION)." >&2; exit 1; }
[[ -s /etc/gitlab/gitlab.rb ]] || { echo "Refus : /etc/gitlab/gitlab.rb absent." >&2; exit 1; }
[[ -s /etc/gitlab/ssl/git01.par1.medisphere.internal.crt ]] || { echo "Refus : certificat absent." >&2; exit 1; }

apt-get update -q
apt-get install -y curl ca-certificates

# Dépôt officiel : script téléchargé, lu (étape 13 de l'énoncé), puis exécuté.
if ! grep -rqs "packages.gitlab.com" /etc/apt/sources.list.d/; then
  curl -fsSLo /root/script.deb.sh https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh
  bash /root/script.deb.sh
fi

EXTERNAL_URL="https://git01.par1.medisphere.internal" apt-get install -y "gitlab-ce=${VERSION}"
apt-mark hold gitlab-ce
gitlab-ctl reconfigure
gitlab-ctl status
