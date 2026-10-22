#!/usr/bin/env bash
# outils/verifier-chiffres.sh — formation/sops-labo (M25-E18, PLAT-2618).
# Refuse (code 1) un dépôt où :
#   - un objet « kind: Secret » est versionné ailleurs que dans un fichier *.sops.yaml ;
#   - un fichier *.sops.yaml n'a pas de métadonnées SOPS (mac, version) ou n'a aucun destinataire ;
#   - une valeur sous data/stringData d'un *.sops.yaml n'est pas chiffrée (ENC[AES256_GCM,…]).
# Ne déchiffre RIEN (aucun accès au coffre) : utilisable dans un pipeline de MR, même non protégé.
# Usage : outils/verifier-chiffres.sh [dossier]   (défaut : k8s). Requiert yq v4 (mikefarah).
set -euo pipefail

dossier="${1:-k8s}"
erreurs=0
signaler() { printf 'verifier-chiffres : %s\n' "$*" >&2; erreurs=$((erreurs + 1)); }

yq --version 2>/dev/null | grep -q mikefarah || { echo "verifier-chiffres : yq v4 (mikefarah) introuvable" >&2; exit 2; }
[[ -d "$dossier" ]] || { echo "verifier-chiffres : dossier $dossier absent" >&2; exit 2; }

while IFS= read -r -d '' f; do
  if [[ "$f" != *.sops.yaml ]]; then
    # Un Secret en clair : chaque document du fichier est examiné (fichiers multi-documents).
    if yq -e 'select(.kind == "Secret")' "$f" >/dev/null 2>&1; then
      signaler "$f : objet Secret hors d'un fichier *.sops.yaml (en clair ?)"
    fi
    continue
  fi
  if ! yq -e '.sops.mac and .sops.version' "$f" >/dev/null 2>&1; then
    signaler "$f : pas de métadonnées SOPS (fichier jamais chiffré ?)"
    continue
  fi
  if ! yq -e '((.sops.hc_vault // []) + (.sops.age // [])) | length > 0' "$f" >/dev/null 2>&1; then
    signaler "$f : aucun destinataire (hc_vault ou age)"
  fi
  # Toute feuille sous data ou stringData doit être un ENC[…] ; on liste les chemins fautifs.
  clairs="$(yq -r '[(.data, .stringData) | select(. != null) | .. | select(tag != "!!map" and tag != "!!seq")
                   | select((tag == "!!str" and test("^ENC\\[AES256_GCM,")) | not) | path | join(".")] | .[]' "$f")"
  if [[ -n "$clairs" ]]; then
    while IFS= read -r chemin; do
      signaler "$f : valeur en clair sous $chemin"
    done <<<"$clairs"
  fi
done < <(find "$dossier" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

if ((erreurs > 0)); then
  echo "verifier-chiffres : $erreurs problème(s)" >&2
  exit 1
fi
echo "verifier-chiffres : aucun secret en clair sous $dossier"
