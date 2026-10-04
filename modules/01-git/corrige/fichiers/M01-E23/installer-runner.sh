#!/usr/bin/env bash
# =============================================================================
# installer-runner.sh — prépare runner01 : PKI, GitLab Runner, outils des jobs (M01-E23)
#
# À lancer en root sur runner01, APRÈS avoir copié la racine de la PKI provisoire :
#   admin@adm01:~$ scp ~/pki-provisoire/ca.crt runner01:/tmp/medisphere-provisoire.crt
#   admin@runner01:~$ sudo RUNNER_VERSION=19.4.<Z> ./installer-runner.sh
#
# Variables :
#   RUNNER_VERSION    (obligatoire) version exacte de GitLab Runner, ex. 19.4.1
#                     (liste : apt-cache madison gitlab-runner, après ajout du dépôt)
#   GITLEAKS_VERSION  défaut 8.30.1
#   UV_VERSION        défaut : dernière version (préfère une version précise, ex. 0.12.3)
#   PRECOMMIT_SPEC    défaut 'pre-commit>=4.6,<4.7'
#
# Ne fait PAS l'enregistrement (le jeton glrt- est un secret : voir le corrigé).
# Rejouable : chaque étape vérifie l'existant.
# =============================================================================
set -euo pipefail

RUNNER_VERSION="${RUNNER_VERSION:?RUNNER_VERSION obligatoire, ex. RUNNER_VERSION=19.4.1}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
UV_VERSION="${UV_VERSION:-}"
PRECOMMIT_SPEC="${PRECOMMIT_SPEC:-pre-commit>=4.6,<4.7}"
CA_SRC=/tmp/medisphere-provisoire.crt
CA_DEST=/usr/local/share/ca-certificates/medisphere-provisoire.crt
GITLAB=https://git01.par1.medisphere.internal

[[ $EUID -eq 0 ]] || { echo "À lancer en root (sudo)." >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== 1. Racine de la PKI provisoire"
if [[ -f "$CA_SRC" ]]; then
  install -o root -g root -m 0644 "$CA_SRC" "$CA_DEST"
  update-ca-certificates
fi
[[ -f "$CA_DEST" ]] || { echo "Racine absente : copie ~/pki-provisoire/ca.crt dans $CA_SRC" >&2; exit 1; }
curl -fsS -o /dev/null "$GITLAB/users/sign_in" && echo "TLS vers git01 : OK (sans -k)"

echo "== 2. Paquets de base"
apt-get update -q
apt-get install -y -q git curl ca-certificates

echo "== 3. Dépôt de paquets GitLab Runner"
if [[ ! -f /etc/apt/sources.list.d/runner_gitlab-runner.list && ! -f /etc/apt/sources.list.d/runner_gitlab-runner.sources ]]; then
  curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" -o "$TMP/script.deb.sh"
  echo "Script du dépôt téléchargé ($(wc -l < "$TMP/script.deb.sh") lignes) : relis-le avant (less $TMP/script.deb.sh)."
  bash "$TMP/script.deb.sh"
fi
apt-cache madison gitlab-runner | head -n 5

echo "== 4. GitLab Runner $RUNNER_VERSION et images d'assistance de la même version"
apt-mark unhold gitlab-runner gitlab-runner-helper-images >/dev/null 2>&1 || true
apt-get install -y -q "gitlab-runner=${RUNNER_VERSION}-1" "gitlab-runner-helper-images=${RUNNER_VERSION}-1"
apt-mark hold gitlab-runner gitlab-runner-helper-images
gitlab-runner --version | head -n 2
# Aucun droit d'administration pour l'utilisateur des jobs.
if id -nG gitlab-runner | grep -qwE 'sudo|adm|docker'; then
  echo "ATTENTION : gitlab-runner appartient à un groupe privilégié : $(id -nG gitlab-runner)" >&2
fi

echo "== 5. uv (pour tous les utilisateurs, dans /usr/local/bin)"
if ! command -v uv >/dev/null 2>&1; then
  url="https://astral.sh/uv/install.sh"
  [[ -n "$UV_VERSION" ]] && url="https://astral.sh/uv/${UV_VERSION}/install.sh"
  curl -LsSf "$url" -o "$TMP/uv-install.sh"
  env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh "$TMP/uv-install.sh"
fi
uv --version

echo "== 6. pre-commit (outil uv partagé : /opt/uv-tools, binaire dans /usr/local/bin)"
export UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin
# Python du système (Debian 13 : 3.13) : un Python téléchargé par uv irait dans
# le dossier personnel de root, illisible par gitlab-runner.
uv tool install --python /usr/bin/python3 "$PRECOMMIT_SPEC"
chmod -R go+rX /opt/uv-tools
sudo -u gitlab-runner -H pre-commit --version

echo "== 7. gitleaks $GITLEAKS_VERSION (binaire officiel, empreinte vérifiée)"
if ! gitleaks version 2>/dev/null | grep -qx "$GITLEAKS_VERSION"; then
  base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"
  archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  curl -fsSL -o "$TMP/$archive" "$base/$archive"
  curl -fsSL -o "$TMP/sommes.txt" "$base/gitleaks_${GITLEAKS_VERSION}_checksums.txt"
  (cd "$TMP" && grep " ${archive}\$" sommes.txt | sha256sum -c -)
  tar -xzf "$TMP/$archive" -C "$TMP" gitleaks
  install -o root -g root -m 0755 "$TMP/gitleaks" /usr/local/bin/gitleaks
fi
sudo -u gitlab-runner -H gitleaks version

echo "== Terminé. Étape suivante : enregistrement du runner (jeton glrt-)."
