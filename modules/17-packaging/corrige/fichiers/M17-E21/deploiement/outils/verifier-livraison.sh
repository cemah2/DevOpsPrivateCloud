#!/usr/bin/env bash
# verifier-livraison.sh — garde-fou de CI de mediagenda/deploiement (M17-E21, INC-4421).
# Pour chaque overlay : le rendu (kubectl kustomize) doit livrer EXACTEMENT la version de son
# livraison.yaml (image de l'API, conteneur de migration, MEDIAGENDA_VERSION). Pour la prod : aucun
# réglage de débogage (component « debogage », DEBUG, format texte) et aucun « images: » dans
# l'overlay (il l'emporterait sur le component « livraison »).
# Usage : outils/verifier-livraison.sh [overlay…]   (défaut : tous les dossiers de overlays/)
# Prérequis : kubectl 1.36 (Kustomize 5.8.1 intégré), yq (mikefarah) 4.x.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"
if (($# == 0)); then
  set -- overlays/*/
fi
echec=0
erreur() { echo "ERREUR $*" >&2; echec=1; }

for o in "$@"; do
  o="${o%/}"
  env="$(basename "$o")"
  [[ -f "$o/livraison.yaml" ]] || continue
  attendu="$(yq -r '.data.version' "$o/livraison.yaml")"
  rendu="$(kubectl kustomize "$o")" || { erreur "$env : rendu impossible"; continue; }
  images="$(yq -r 'select(.kind == "Deployment" and .metadata.name == "mediagenda")
    | (.spec.template.spec.containers + (.spec.template.spec.initContainers // []))[]
    | select(.name == "api" or .name == "migrations") | .image' <<<"$rendu" | sed -E 's/.*:([^:/]+)$/\1/' | sort -u)"
  [[ "$images" == "$attendu" ]] || erreur "$env : images rendues « $(tr '\n' ' ' <<<"$images")» ≠ livraison.yaml « $attendu »"
  version="$(yq -r 'select(.kind == "Deployment" and .metadata.name == "mediagenda")
    | .spec.template.spec.containers[] | select(.name == "api") | .env[] | select(.name == "MEDIAGENDA_VERSION") | .value' <<<"$rendu")"
  [[ "$version" == "$attendu" ]] || erreur "$env : MEDIAGENDA_VERSION « $version » ≠ « $attendu »"
  if [[ "$env" == prod ]]; then
    if yq -e '.images' "$o/kustomization.yaml" >/dev/null 2>&1; then
      erreur "prod : « images: » interdit dans l'overlay (la version se change dans livraison.yaml)"
    fi
    if yq -e '.components[] | select(test("debogage"))' "$o/kustomization.yaml" >/dev/null 2>&1; then
      erreur "prod : component debogage interdit"
    fi
    if yq -e 'select(.kind == "Deployment") | .spec.template.spec.containers[].env[]
        | select((.name == "MEDIAGENDA_LOG_LEVEL" and .value == "DEBUG") or (.name == "MEDIAGENDA_LOG_FORMAT" and .value == "texte"))' <<<"$rendu" >/dev/null 2>&1; then
      erreur "prod : réglages de débogage dans le rendu"
    fi
  fi
  ((echec)) || echo "$env : $attendu, conforme"
done
exit "$echec"
