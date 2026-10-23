#!/usr/bin/env bash
# outils/rendre-charts.sh (plateforme/gitops) — M29-E02, PLAT-3002.
#
# Rend, comme le ferait Argo CD, chaque Application de plateforme/ dont une source est un chart du
# miroir Harbor (registry.par1.medisphere.internal/charts), avec ses fichiers de valeurs de CE dépôt
# ($values/valeurs/<composant>/…), pour que kubeconform valide ce qui sera VRAIMENT appliqué.
#   outils/rendre-charts.sh [DOSSIER_SORTIE]     (défaut : rendu) → rendu/<application>.yaml
#
# Variables :
#   SCHEMAS                dossier du paquet schemas-crd (api-versions.txt), défaut : schemas
#   KUBERNETES_VERSION     version du cluster pour --kube-version (défaut 1.36.5)
#   HARBOR_CHARTS_RO_USER, HARBOR_CHARTS_RO_TOKEN   robot$charts+lecture (M17), si pas déjà connecté
#   CHARTS_LOCAUX          dossier d'archives <chart>-<version>.tgz déjà présentes (pas de pull)
#   REF_<nom>              chemin local d'un autre dépôt référencé par « ref: <nom> » (ex. REF_politiques)
# Une Application dont un fichier de valeurs vient d'un dépôt non fourni est SIGNALÉE et sautée
# (code de sortie 3 à la fin) : on ne valide jamais un rendu incomplet en silence.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sortie="${1:-rendu}"
SCHEMAS="${SCHEMAS:-schemas}"
KUBE="${KUBERNETES_VERSION:-1.36.5}"
DEPOT_CHARTS="registry.par1.medisphere.internal/charts"
travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
mkdir -p "$sortie"
sautees=0

# --api-versions : ce que le cluster sert (les charts testent .Capabilities.APIVersions.Has).
api_versions=()
if [[ -f "$SCHEMAS/api-versions.txt" ]]; then
  while IFS= read -r v; do api_versions+=(--api-versions "$v"); done <"$SCHEMAS/api-versions.txt"
else
  echo "avertissement : $SCHEMAS/api-versions.txt absent, rendu sans les API du cluster" >&2
fi

if [[ -z "${CHARTS_LOCAUX:-}" && -n "${HARBOR_CHARTS_RO_USER:-}" ]]; then
  printf '%s' "${HARBOR_CHARTS_RO_TOKEN:?}" | helm registry login registry.par1.medisphere.internal \
    --username "$HARBOR_CHARTS_RO_USER" --password-stdin >/dev/null
fi

for app in plateforme/*.yaml; do
  [[ "$(yq '.kind' "$app")" == "Application" ]] || continue
  nom="$(yq '.metadata.name' "$app")"
  espace="$(yq '.spec.destination.namespace // "default"' "$app")"
  # Première source « chart » venant du miroir Harbor (sources multiples ou source unique).
  source="$(yq -o=json -I=0 '[(.spec.sources // [.spec.source])[] | select(.chart != null)][0] // ""' "$app")"
  [[ -n "$source" && "$source" != '""' ]] || continue
  depot="$(jq -r '.repoURL' <<<"$source")"
  [[ "$depot" == "$DEPOT_CHARTS" ]] || { echo "$nom : chart hors du miroir ($depot), refusé" >&2; exit 1; }
  chart="$(jq -r '.chart' <<<"$source")"
  version="$(jq -r '.targetRevision' <<<"$source")"
  release="$(jq -r '.helm.releaseName // empty' <<<"$source")"
  release="${release:-$nom}"

  # Fichiers de valeurs : « $values/… » = ce dépôt ; « $<ref>/… » = REF_<ref> s'il est fourni.
  valeurs=()
  manquant=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    ref="${f%%/*}"
    ref="${ref#\$}"
    chemin="${f#*/}"
    if [[ "$ref" == "values" ]]; then
      valeurs+=(-f "$chemin")
    else
      var="REF_${ref//-/_}"
      if [[ -n "${!var:-}" ]]; then
        valeurs+=(-f "${!var}/$chemin")
      else
        manquant="$f"
      fi
    fi
  done < <(jq -r '.helm.valueFiles[]? // empty' <<<"$source")
  if [[ -n "$manquant" ]]; then
    echo "$nom : valeurs $manquant d'un autre dépôt (fournis REF_${manquant%%/*}) : SAUTÉE" | tr -d '$' >&2
    sautees=$((sautees + 1))
    continue
  fi

  if [[ -n "${CHARTS_LOCAUX:-}" ]]; then
    archive="$CHARTS_LOCAUX/$chart-$version.tgz"
  else
    helm pull "oci://$DEPOT_CHARTS/$chart" --version "$version" --destination "$travail" >/dev/null
    archive="$travail/$chart-$version.tgz"
  fi
  helm template "$release" "$archive" --namespace "$espace" --kube-version "$KUBE" \
    "${api_versions[@]}" "${valeurs[@]}" >"$sortie/$nom.yaml"
  echo "$nom : $chart $version → $sortie/$nom.yaml ($(grep -c '^kind:' "$sortie/$nom.yaml") objets)"
done

if ((sautees > 0)); then
  echo "$sautees application(s) non rendue(s) : rendu INCOMPLET" >&2
  exit 3
fi
