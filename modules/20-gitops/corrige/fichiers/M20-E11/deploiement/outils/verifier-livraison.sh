#!/usr/bin/env bash
# verifier-livraison.sh — garde-fou de CI de mediagenda/deploiement (M17-E21, INC-4421 ; règle des
# images par empreinte : M19-E17, PLAT-2017 ; Job de migration : M20-E11, DEV-2111).
# Pour chaque overlay : le rendu (kubectl kustomize) doit livrer EXACTEMENT la version de son
# livraison.yaml (image de l'API, Job de migration mediagenda-migrate depuis M20-E11 — le conteneur
# d'initialisation « migrations » a disparu du rendu —, MEDIAGENDA_VERSION).
# Images par empreinte (M19-E17) : un « images: » dans un overlay l'emporte sur le component
# « livraison » (M17-E21). Il n'est donc admis que sous une forme : une seule entrée, pour l'image de
# l'API, dont l'étiquette (newTag) est la version de livraison.yaml ET qui porte une empreinte
# (digest). Le rendu donne alors « …/mediagenda-api:vX.Y.Z@sha256:… » (constaté avec kustomize 5.8.1).
# Toute autre entrée « images: » est refusée. Pour la prod, en plus : aucun réglage de débogage.
# Usage : outils/verifier-livraison.sh [overlay…]   (défaut : tous les dossiers de overlays/)
# Prérequis : kubectl 1.36 (Kustomize 5.8.1 intégré), yq (mikefarah) 4.x.
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"
if (($# == 0)); then
  set -- overlays/*/
fi
image_api="registry.par1.medisphere.internal/medisphere/mediagenda-api"
echec=0
erreur() { echo "ERREUR $*" >&2; echec=1; }

for o in "$@"; do
  o="${o%/}"
  env="$(basename "$o")"
  [[ -f "$o/livraison.yaml" ]] || continue
  attendu="$(yq -r '.data.version' "$o/livraison.yaml")"

  # 1. « images: » de l'overlay : au plus l'image de l'API, à la version de livraison.yaml, par empreinte.
  if yq -e '.images' "$o/kustomization.yaml" >/dev/null 2>&1; then
    autres="$(I="$image_api" yq -r '.images[] | select(.name != strenv(I)) | .name' "$o/kustomization.yaml")"
    [[ -z "$autres" ]] || erreur "$env : « images: » interdit pour : $(tr '\n' ' ' <<<"$autres")"
    etiquette="$(I="$image_api" yq -r '.images[] | select(.name == strenv(I)) | .newTag // ""' "$o/kustomization.yaml")"
    empreinte="$(I="$image_api" yq -r '.images[] | select(.name == strenv(I)) | .digest // ""' "$o/kustomization.yaml")"
    [[ "$etiquette" == "$attendu" ]] || erreur "$env : images[].newTag « $etiquette » ≠ livraison.yaml « $attendu »"
    [[ "$empreinte" =~ ^sha256:[a-f0-9]{64}$ ]] || erreur "$env : images[] sans empreinte valide (digest)"
  fi

  # 2. Le rendu : étiquette (avant l'éventuelle empreinte) et MEDIAGENDA_VERSION = livraison.yaml.
  rendu="$(kubectl kustomize "$o")" || { erreur "$env : rendu impossible"; continue; }
  images="$({ yq -r 'select(.kind == "Deployment" and .metadata.name == "mediagenda")
      | (.spec.template.spec.containers + (.spec.template.spec.initContainers // []))[]
      | select(.name == "api" or .name == "migrations") | .image' <<<"$rendu"
    yq -r 'select(.kind == "Job" and .metadata.name == "mediagenda-migrate")
      | .spec.template.spec.containers[] | select(.name == "migrate") | .image' <<<"$rendu"; } \
    | grep -v '^---$' \
    | sed -E 's/@sha256:[a-f0-9]{64}$//; s/.*:([^:/]+)$/\1/' | sort -u)"
  [[ "$images" == "$attendu" ]] || erreur "$env : images rendues « $(tr '\n' ' ' <<<"$images")» ≠ livraison.yaml « $attendu »"
  # M20-E11 : le Job de migration est présent et suit la même image que l'API.
  yq -e 'select(.kind == "Job" and .metadata.name == "mediagenda-migrate")' <<<"$rendu" >/dev/null 2>&1 \
    || erreur "$env : Job mediagenda-migrate absent du rendu (component migrations)"
  version="$(yq -r 'select(.kind == "Deployment" and .metadata.name == "mediagenda")
    | .spec.template.spec.containers[] | select(.name == "api") | .env[] | select(.name == "MEDIAGENDA_VERSION") | .value' <<<"$rendu")"
  [[ "$version" == "$attendu" ]] || erreur "$env : MEDIAGENDA_VERSION « $version » ≠ « $attendu »"

  # 3. Prod : ni component de débogage, ni réglage de débogage dans le rendu.
  if [[ "$env" == prod ]]; then
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
