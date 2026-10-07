#!/usr/bin/env bash
# valider-syntaxe.sh — « packer validate -syntax-only » sur chaque image du projet (M03-E02).
# Utilisé par le hook pre-commit « packer-validate ». Ne demande ni secret, ni plugin, ni
# accès à Proxmox : il attrape les erreurs de syntaxe HCL et les références cassées
# (variable inconnue, fichier templatefile() absent…). La validation complète, avec les
# variables et le plugin, est faite par outils/construire.sh et par la CI (M03-E15).
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CHECKPOINT_DISABLE=1
rc=0
shopt -s nullglob
for build in "$racine"/*/build.pkr.hcl; do
  dossier="$(dirname "$build")"
  if ! (cd "$dossier" && packer validate -syntax-only . >/dev/null); then
    echo "erreur de syntaxe : ${dossier#"$racine"/}" >&2
    rc=1
  fi
done
exit "$rc"
