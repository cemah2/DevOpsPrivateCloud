#!/usr/bin/env bash
# outils/schemas-crd.sh (plateforme/k8s) — M29-E02, PLAT-3002. Remplace la version de M16-E23.
#
# Schémas JSON des CRD pour kubeconform, tirés du CLUSTER (toutes les CRD réellement servies, à
# leur version réelle), convertis par le script officiel de kubeconform (openapi2jsonschema.py,
# v0.8.0, recopié dans outils/ et vérifié par empreinte), puis publiés comme paquet générique
# GitLab « schemas-crd » de plateforme/k8s, que les CI des autres dépôts téléchargent.
#
# Pourquoi le script officiel plutôt que « jq .schema.openAPIV3Schema » (M16) : il ajoute
# additionalProperties: false à chaque objet qui déclare ses propriétés. Sans cela, kubeconform
# -strict ACCEPTE un champ mal orthographié dans une ressource personnalisée (spec.durration…).
# DENY_ROOT_ADDITIONAL_PROPERTIES=1 l'applique aussi à la racine de l'objet (sinon « specc: » passe).
#
# Usage :
#   outils/schemas-crd.sh generer [DOSSIER]          (défaut : schemas) — lit le cluster
#   outils/schemas-crd.sh publier VERSION [DOSSIER]  archive + paquet générique (VERSION : AAAA.MM.JJ)
#   outils/schemas-crd.sh verifier [DOSSIER]         rejoue les manifestes du dépôt contre DOSSIER
# Variables :
#   KUBECTL_CONTEXTE  contexte kubectl (défaut : k8s-par1 ; lecture des CRD seulement)
#   SOURCE_CRD        fichier YAML/JSON de CRD à lire AU LIEU du cluster (essais, rédaction)
#   GITLAB_URL        (défaut https://git01.par1.medisphere.internal)
#   GITLAB_JETON      fichier du jeton d'écriture (défaut ~/.config/workbook/gitlab-admin.token)
# Disposition produite : DOSSIER/<groupe>/<kind-minuscule>_<version>.json, plus
# DOSSIER/api-versions.txt (sortie de « kubectl api-versions » : --api-versions de helm template)
# et DOSSIER/LISEZMOI (provenance). kubeconform les lit avec :
#   -schema-location default -schema-location 'DOSSIER/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONVERTISSEUR=outils/openapi2jsonschema.py
# Empreinte de scripts/openapi2jsonschema.py à l'étiquette v0.8.0 de yannh/kubeconform.
CONVERTISSEUR_SHA256=d145babfbb765004030764e1b4e518bfb7a4bd7f111691a08fa57983b81881f3
CONTEXTE="${KUBECTL_CONTEXTE:-k8s-par1}"
GITLAB_URL="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
JETON_FICHIER="${GITLAB_JETON:-$HOME/.config/workbook/gitlab-admin.token}"
PROJET="plateforme%2Fk8s"

erreur() { echo "schemas-crd : $*" >&2; exit 1; }

verifier_convertisseur() {
  [[ -f "$CONVERTISSEUR" ]] || erreur "$CONVERTISSEUR absent (copie de kubeconform v0.8.0, voir LISEZMOI)"
  echo "$CONVERTISSEUR_SHA256  $CONVERTISSEUR" | sha256sum --check --quiet \
    || erreur "$CONVERTISSEUR ne correspond pas à l'empreinte attendue"
}

lire_crd() {
  if [[ -n "${SOURCE_CRD:-}" ]]; then
    yq -o=json -I=0 'select(.kind == "CustomResourceDefinition")' "$SOURCE_CRD"
  else
    kubectl --context "$CONTEXTE" get customresourcedefinitions -o json | jq -c '.items[]'
  fi
}

generer() {
  local sortie="${1:-schemas}" travail n=0 ligne groupe
  verifier_convertisseur
  command -v python3 >/dev/null || erreur "python3 requis"
  python3 -c 'import yaml' 2>/dev/null || erreur "module Python yaml requis (uv run --with pyyaml, ou python3-yaml)"
  travail="$(mktemp -d)"
  # shellcheck disable=SC2064  # le chemin est figé au moment du piège, c'est voulu
  trap "rm -rf '$travail'" EXIT
  rm -rf "$sortie"
  mkdir -p "$sortie"
  # Une CRD par fichier, rangée par groupe : le convertisseur écrit dans le dossier COURANT
  # (il ne garde que le nom de fichier), d'où un appel par groupe depuis son dossier.
  while IFS= read -r ligne; do
    groupe="$(jq -r '.spec.group' <<<"$ligne")"
    mkdir -p "$travail/$groupe" "$sortie/$groupe"
    n=$((n + 1))
    jq '.' <<<"$ligne" >"$travail/$groupe/crd-$n.json"
  done < <(lire_crd)
  ((n > 0)) || erreur "aucune CRD lue (contexte $CONTEXTE, ou SOURCE_CRD vide)"
  for dossier in "$travail"/*/; do
    groupe="$(basename "$dossier")"
    (cd "$sortie/$groupe" && FILENAME_FORMAT='{kind}_{version}' DENY_ROOT_ADDITIONAL_PROPERTIES=1 \
      python3 "$OLDPWD/$CONVERTISSEUR" "$dossier"/crd-*.json >/dev/null)
  done
  if [[ -z "${SOURCE_CRD:-}" ]]; then
    kubectl --context "$CONTEXTE" api-versions >"$sortie/api-versions.txt"
  fi
  {
    echo "Schémas des CRD de k8s-par1 pour kubeconform (plateforme/k8s, outils/schemas-crd.sh)."
    echo "Générés le $(date -u +%Y-%m-%dT%H:%M:%SZ) depuis ${SOURCE_CRD:-le contexte $CONTEXTE}, $n CRD."
    echo "Convertisseur : kubeconform v0.8.0 scripts/openapi2jsonschema.py (sha256 $CONVERTISSEUR_SHA256)."
  } >"$sortie/LISEZMOI"
  echo "schemas-crd : $n CRD, $(find "$sortie" -name '*.json' | wc -l) schémas dans $sortie/"
}

publier() {
  local version="${1:?VERSION (AAAA.MM.JJ) attendue}" sortie="${2:-schemas}" archive
  [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[0-9]+)?$ ]] || erreur "version $version : AAAA.MM.JJ[-N] attendu"
  [[ -d "$sortie" && -f "$sortie/LISEZMOI" ]] || erreur "$sortie/ absent : lance d'abord « generer »"
  [[ -r "$JETON_FICHIER" ]] || erreur "jeton illisible : $JETON_FICHIER"
  archive="$(mktemp -d)/schemas-crd.tar.gz"
  # Archive reproductible : ordre, dates et propriétaires fixés (même contenu = même empreinte).
  tar --sort=name --mtime='2000-01-01 00:00Z' --owner=0 --group=0 --numeric-owner \
    -C "$sortie" -czf "$archive" .
  (cd "$(dirname "$archive")" && sha256sum schemas-crd.tar.gz >schemas-crd.tar.gz.sha256)
  for f in schemas-crd.tar.gz schemas-crd.tar.gz.sha256; do
    # Jeton par un en-tête lu dans une substitution de processus : jamais sur la ligne de commande.
    curl -sS --fail -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_FICHIER")") \
      --upload-file "$(dirname "$archive")/$f" \
      "$GITLAB_URL/api/v4/projects/$PROJET/packages/generic/schemas-crd/$version/$f" >/dev/null
  done
  echo "schemas-crd $version publié : $(cut -d' ' -f1 "$(dirname "$archive")/schemas-crd.tar.gz.sha256")"
}

verifier() {
  local sortie="${1:-schemas}"
  kubeconform -strict -summary -kubernetes-version "${KUBERNETES_VERSION:-1.36.5}" \
    -schema-location default \
    -schema-location "$sortie/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    -ignore-filename-pattern 'values\.yaml$' -ignore-filename-pattern '\.extrait' \
    -ignore-filename-pattern 'kustomization\.yaml$' \
    composants/ espaces/ rbac/ admission/
}

case "${1:-}" in
  generer) shift; generer "$@" ;;
  publier) shift; publier "$@" ;;
  verifier) shift; verifier "$@" ;;
  *) echo "usage : $0 generer [DOSSIER] | publier VERSION [DOSSIER] | verifier [DOSSIER]" >&2; exit 2 ;;
esac
