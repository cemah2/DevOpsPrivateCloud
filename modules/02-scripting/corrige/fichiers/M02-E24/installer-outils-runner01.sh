#!/usr/bin/env bash
# installer-outils-runner01.sh — outils de CI de plateforme/outils sur runner01 (M02-E24, PLAT-354).
#
# Mêmes outils, mêmes versions et même provenance que sur adm01 (00-introduction du module) :
#   ShellCheck 0.11.0 (dépôt Debian trixie-backports, signé) → /usr/bin/shellcheck
#   shfmt 3.14.1 (binaire de la release)                       → /usr/local/bin/shfmt
#   jq 1.8.2 (binaire de la release ; Debian livre la 1.7.1)   → /usr/local/bin/jq
#   bats-core 1.13.0 (archive de l'étiquette)                  → /opt/bats, lien /usr/local/bin/bats
#   Task 3.54.0 (archive de la release)                        → /usr/local/bin/task
# uv est déjà présent (M01-E23/E24).
# Idempotent : un outil déjà présent dans la bonne version n'est pas retéléchargé.
#
# Usage (sur runner01, en root) : sudo ./installer-outils-runner01.sh
#
# ⚠️ Les empreintes SHA-256 sont à fournir par l'environnement (ou à écrire ci-dessous) :
# celles que tu as vérifiées et notées en installant adm01 (page de release, task_checksums.txt,
# sha256sum.txt de jq ; pour bats, l'empreinte que tu as calculée). Le script refuse d'installer
# sans empreinte : un binaire exécuté par tous les pipelines ne s'installe jamais « à l'aveugle ».
#   sudo SHFMT_SHA256=… JQ_SHA256=… BATS_SHA256=… TASK_SHA256=… ./installer-outils-runner01.sh
set -euo pipefail

SHELLCHECK_VERSION=0.11.0
JQ_VERSION=1.8.2
JQ_SHA256="${JQ_SHA256:-}"
SHFMT_VERSION=3.14.1
SHFMT_SHA256="${SHFMT_SHA256:-}"
BATS_VERSION=1.13.0
BATS_SHA256="${BATS_SHA256:-}"
TASK_VERSION=3.54.0
TASK_SHA256="${TASK_SHA256:-}"

GH=https://github.com
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

[[ "$EUID" -eq 0 ]] || { echo "à lancer en root (sudo)" >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || { echo "architecture non prévue : $(uname -m)" >&2; exit 1; }

# telecharger URL FICHIER EMPREINTE — télécharge puis vérifie l'empreinte SHA-256.
telecharger() {
  local url="$1" dest="$2" attendu="$3"
  [[ "$attendu" =~ ^[0-9a-f]{64}$ ]] || {
    echo "empreinte SHA-256 manquante ou invalide pour $url : renseigne-la (voir l'en-tête)" >&2
    exit 1
  }
  curl -fsSL --proto '=https' --retry 3 -o "$dest" "$url"
  echo "$attendu  $dest" | sha256sum -c --quiet - || { echo "EMPREINTE INCORRECTE : $url" >&2; exit 1; }
}

# deja VERSION COMMANDE... — vrai si la sortie de la commande contient la version attendue.
deja() {
  local v="$1"
  shift
  "$@" 2>/dev/null | grep -qF -- "$v"
}

if deja "$SHELLCHECK_VERSION" shellcheck --version; then
  echo "ShellCheck $SHELLCHECK_VERSION déjà installé"
else
  # Les rétroportages ne sont installés qu'à la demande (-t) : il faut que le dépôt soit déclaré.
  if ! apt-cache policy shellcheck | grep -q trixie-backports; then
    echo "dépôt trixie-backports absent : déclare-le comme sur adm01 (00-introduction), puis relance" >&2
    exit 1
  fi
  apt-get install -y -t trixie-backports shellcheck
fi

if deja "$JQ_VERSION" jq --version; then
  echo "jq $JQ_VERSION déjà installé"
else
  telecharger "$GH/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-amd64" "$tmp/jq" "$JQ_SHA256"
  install -m 0755 "$tmp/jq" /usr/local/bin/jq
fi

if deja "$SHFMT_VERSION" shfmt --version; then
  echo "shfmt $SHFMT_VERSION déjà installé"
else
  telecharger "$GH/mvdan/sh/releases/download/v$SHFMT_VERSION/shfmt_v${SHFMT_VERSION}_linux_amd64" \
    "$tmp/shfmt" "$SHFMT_SHA256"
  install -m 0755 "$tmp/shfmt" /usr/local/bin/shfmt
fi

if deja "$BATS_VERSION" bats --version; then
  echo "bats-core $BATS_VERSION déjà installé"
else
  telecharger "$GH/bats-core/bats-core/archive/refs/tags/v$BATS_VERSION.tar.gz" \
    "$tmp/bats.tar.gz" "$BATS_SHA256"
  tar -xzf "$tmp/bats.tar.gz" -C "$tmp"
  rm -rf /opt/bats
  "$tmp/bats-core-$BATS_VERSION/install.sh" /opt/bats
  ln -sfn /opt/bats/bin/bats /usr/local/bin/bats
fi

if deja "$TASK_VERSION" task --version; then
  echo "Task $TASK_VERSION déjà installé"
else
  telecharger "$GH/go-task/task/releases/download/v$TASK_VERSION/task_linux_amd64.tar.gz" \
    "$tmp/task.tar.gz" "$TASK_SHA256"
  tar -xzf "$tmp/task.tar.gz" -C "$tmp" task
  install -m 0755 "$tmp/task" /usr/local/bin/task
fi

# Contrôle final, tel que le verra le compte gitlab-runner.
for c in shellcheck shfmt jq bats task uv; do
  printf '%-10s %s\n' "$c" "$(sudo -u gitlab-runner -H bash -lc "command -v $c" || echo ABSENT)"
done
shellcheck --version | sed -n 2p
shfmt --version
jq --version
bats --version
task --version
