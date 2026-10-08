#!/usr/bin/env bash
# outils/inventaire.sh — produit inventaire/multinode (M10-E03).
#
# = nos groupes principaux (inventaire/groupes-principaux.ini)
# + les groupes de SERVICES de l'exemple « multinode » livré avec la version installée de
#   Kolla-Ansible, privés de leurs propres groupes principaux.
# Pourquoi : les groupes de services changent d'une version à l'autre (2026.1 : « common »
# devient « kolla_toolbox », « kolla_logs » apparaît, groupes LVM de Cinder…). Recopier un
# inventaire d'un tutoriel ou d'une version précédente casse le déploiement en silence.
#
# Usage (depuis la racine du dépôt) : outils/inventaire.sh [--verifier]
#   --verifier : n'écrit rien, échoue si inventaire/multinode n'est pas à jour (CI, revue).
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"

prefixe="$(uv run --quiet python -c 'import sys; print(sys.prefix)')"
exemple="$prefixe/share/kolla-ansible/ansible/inventory/multinode"
[[ -r "$exemple" ]] || { echo "inventaire.sh : exemple introuvable : $exemple (uv sync ?)" >&2; exit 1; }
version="$(uv run --quiet python -c 'from importlib.metadata import version; print(version("kolla-ansible"))')"

sortie="$(mktemp)"
trap 'rm -f "$sortie"' EXIT

{
  echo "# inventaire/multinode — PRODUIT par outils/inventaire.sh, ne pas modifier à la main."
  echo "# Groupes principaux : inventaire/groupes-principaux.ini"
  echo "# Groupes de services : exemple « multinode » de kolla-ansible $version"
  echo
  cat inventaire/groupes-principaux.ini
  echo
  echo "# ---- Groupes de services (kolla-ansible $version, inchangés) ----"
  # On retire de l'exemple les sections que nous définissons nous-mêmes.
  awk '
    BEGIN { split("control network compute monitoring storage deployment", n, " "); for (i in n) nos[n[i]] = 1 }
    /^\[/ { nom = $0; gsub(/[\[\]]/, "", nom); sauter = (nom in nos) }
    !sauter { print }
  ' "$exemple"
} >"$sortie"

if [[ "${1:-}" == "--verifier" ]]; then
  if diff -q "$sortie" inventaire/multinode >/dev/null 2>&1; then
    echo "inventaire/multinode est à jour (kolla-ansible $version)."
    exit 0
  fi
  echo "inventaire/multinode n'est pas à jour : relance outils/inventaire.sh et relis le diff." >&2
  exit 1
fi

install -m 0644 "$sortie" inventaire/multinode
echo "inventaire/multinode écrit (kolla-ansible $version). Relis le diff avant de committer."
