#!/usr/bin/env bash
# plateforme/donnees — outils/recopier-operateurs.sh (M27-E03, PLAT-2803)
# Recopie les manifestes de publication des opérateurs RabbitMQ (aucun chart Helm officiel) dans
# vendor/rabbitmq/, à une version DONNÉE, et refuse tout fichier dont l'empreinte SHA-256 diffère de
# celle écrite ci-dessous (relevée à la main, relue en MR). Monter de version = une MR qui change la
# version ET l'empreinte, et dont le diff de vendor/ est relu (CRD, droits, images).
#
# Usage : outils/recopier-operateurs.sh            (depuis la racine du dépôt)
#         outils/recopier-operateurs.sh --verifier (ne télécharge rien : contrôle les copies)
set -euo pipefail

readonly CO_VERSION="2.23.1"
readonly CO_SHA256="ae35a547751656bc64bb734026249a845d226d96aba5a73783e05c5ec3444687"
readonly MTO_VERSION="1.20.4"
readonly MTO_SHA256="11a390b02c74397251cdcbee7efac01b1cafc08ac041cd7ab2d69696b6fac0d8"

readonly CO_URL="https://github.com/rabbitmq/cluster-operator/releases/download/v${CO_VERSION}/cluster-operator.yml"
readonly MTO_URL="https://github.com/rabbitmq/messaging-topology-operator/releases/download/v${MTO_VERSION}/messaging-topology-operator-with-certmanager.yaml"
readonly CO_DEST="vendor/rabbitmq/cluster-operator/cluster-operator-${CO_VERSION}.yml"
readonly MTO_DEST="vendor/rabbitmq/messaging-topology-operator/messaging-topology-operator-with-certmanager-${MTO_VERSION}.yaml"

erreur() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

verifier() { # verifier FICHIER EMPREINTE
  local calcule
  calcule="$(sha256sum "$1" | cut -d' ' -f1)"
  [[ "$calcule" == "$2" ]] || erreur "$1 : empreinte $calcule, attendue $2"
  printf '[OK] %s (%s)\n' "$1" "${2:0:16}…"
}

recopier() { # recopier URL DESTINATION EMPREINTE
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  curl -fsSL --proto '=https' --max-time 60 -o "$tmp" "$1" || erreur "téléchargement impossible : $1"
  verifier "$tmp" "$3"
  mkdir -p "$(dirname "$2")"
  install -m 644 "$tmp" "$2"
  printf '[OK] recopié : %s\n' "$2"
}

[[ -d vendor/rabbitmq ]] || erreur "à lancer depuis la racine de plateforme/donnees"
command -v sha256sum >/dev/null || erreur "sha256sum absent"

if [[ "${1:-}" == "--verifier" ]]; then
  verifier "$CO_DEST" "$CO_SHA256"
  verifier "$MTO_DEST" "$MTO_SHA256"
  exit 0
fi

command -v curl >/dev/null || erreur "curl absent"
recopier "$CO_URL" "$CO_DEST" "$CO_SHA256"
recopier "$MTO_URL" "$MTO_DEST" "$MTO_SHA256"
echo "Relis le diff (git diff --stat vendor/ ; CRD, ClusterRole, images) avant la MR."
