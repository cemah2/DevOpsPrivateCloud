#!/usr/bin/env bash
# verifier-livraison.sh — garde-fou de medidoc/deploiement (M19-E33, DEV-2033), sur le modèle de celui
# de mediagenda/deploiement (M17-E21, M19-E17). Lancé par le composant promotion avant de pousser la
# branche de promotion, et utilisable à la main.
# Pour chaque overlay qui a un livraison.yaml : « images: » ne contient que l'image de MédiDoc, avec
# l'étiquette de livraison.yaml ET une empreinte ; le rendu livre cette version, par empreinte.
# Usage : outils/verifier-livraison.sh [overlay…]   (défaut : tous les dossiers de overlays/)
# Prérequis : kubectl 1.36 (Kustomize intégré), yq (mikefarah) 4.x.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"
if (($# == 0)); then
  set -- overlays/*/
fi
image="registry.par1.medisphere.internal/medisphere/medidoc"
echec=0
erreur() { echo "ERREUR $*" >&2; echec=1; }

for o in "$@"; do
  o="${o%/}"
  env="$(basename "$o")"
  [[ -f "$o/livraison.yaml" ]] || continue
  attendu="$(yq -r '.data.version' "$o/livraison.yaml")"

  autres="$(I="$image" yq -r '(.images // [])[] | select(.name != strenv(I)) | .name' "$o/kustomization.yaml")"
  [[ -z "$autres" ]] || erreur "$env : « images: » interdit pour : $(tr '\n' ' ' <<<"$autres")"
  etiquette="$(I="$image" yq -r '(.images // [])[] | select(.name == strenv(I)) | .newTag // ""' "$o/kustomization.yaml")"
  empreinte="$(I="$image" yq -r '(.images // [])[] | select(.name == strenv(I)) | .digest // ""' "$o/kustomization.yaml")"
  [[ "$etiquette" == "$attendu" ]] || erreur "$env : images[].newTag « $etiquette » ≠ livraison.yaml « $attendu »"
  [[ "$empreinte" =~ ^sha256:[a-f0-9]{64}$ ]] || erreur "$env : image sans empreinte valide (digest)"

  rendu="$(kubectl kustomize "$o")" || { erreur "$env : rendu impossible"; continue; }
  rendue="$(yq -r 'select(.kind == "Deployment" and .metadata.name == "medidoc")
    | .spec.template.spec.containers[] | select(.name == "medidoc") | .image' <<<"$rendu")"
  [[ "$rendue" == "$image:$attendu@$empreinte" ]] || erreur "$env : image rendue « $rendue » ≠ « $image:$attendu@$empreinte »"
  ((echec)) || echo "$env : $attendu, conforme"
done
exit "$echec"
