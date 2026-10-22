#!/bin/sh
# outils/recopier.sh — recopie dans Harbor les charts de charts.tsv (M20-E13).
# POSIX sh : tourne dans l'image alpine/helm (Helm 4.3, sans bash ni yq).
#
# Pour chaque chart :
#   1. déjà dans Harbor à cette version ? → rien à pousser (les étiquettes du projet « charts » sont
#      immuables, M13) ; on relit son digest pour le job de signature ;
#   2. sinon : helm pull depuis l'amont, contrôle de l'empreinte SHA-256 de l'archive, helm push ;
# et ajoute « oci-sans-schéma@digest » à recopies.txt (lu par le job « signer »).
# Variables (CI) : HARBOR_MIROIR_USER, HARBOR_MIROIR_TOKEN (robot$charts+miroir, push+pull sur
# « charts »), MEDISPHERE_ROOT_CA (variable d'instance de type fichier, M13).
set -eu

REGISTRE="registry.par1.medisphere.internal"
DEST="oci://$REGISTRE/charts"
liste="${1:-charts.tsv}"
: "${HARBOR_MIROIR_USER:?}" "${HARBOR_MIROIR_TOKEN:?}" "${MEDISPHERE_ROOT_CA:?}"

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
: >recopies.txt

# --password-stdin : le jeton ne passe jamais en argument (visible par ps).
printf '%s' "$HARBOR_MIROIR_TOKEN" | helm registry login "$REGISTRE" --ca-file "$MEDISPHERE_ROOT_CA" \
  --username "$HARBOR_MIROIR_USER" --password-stdin

tab="$(printf '\t')"
while IFS="$tab" read -r nom depot version empreinte; do
  [ -n "$nom" ] || continue
  echo "== $nom $version"
  if helm show chart "$DEST/$nom" --version "$version" --ca-file "$MEDISPHERE_ROOT_CA" >/dev/null 2>&1; then
    # Déjà recopié : on ne republie pas. Le digest se relit en tirant l'artefact de Harbor.
    helm pull "$DEST/$nom" --version "$version" --ca-file "$MEDISPHERE_ROOT_CA" -d "$travail" >"$travail/pull.log" 2>&1
    digest="$(sed -n 's/^Digest: //p' "$travail/pull.log")"
    echo "   déjà dans Harbor ($digest)"
  else
    case "$depot" in
      oci://*) helm pull "$depot" --version "$version" -d "$travail" ;;
      *) helm pull "$nom" --repo "$depot" --version "$version" -d "$travail" ;;
    esac
    archive="$travail/$nom-$version.tgz"
    recu="sha256:$(sha256sum "$archive" | cut -d ' ' -f 1)"
    if [ "$recu" != "$empreinte" ]; then
      echo "ERREUR $nom $version : empreinte $recu, attendue $empreinte (charts.yaml) : rien n'est poussé" >&2
      exit 1
    fi
    echo "   empreinte conforme"
    helm push "$archive" "$DEST" --ca-file "$MEDISPHERE_ROOT_CA" >"$travail/push.log" 2>&1 || { cat "$travail/push.log" >&2; exit 1; }
    digest="$(sed -n 's/^Digest: //p' "$travail/push.log")"
    echo "   poussé ($digest)"
  fi
  case "$digest" in
    sha256:*) ;;
    *) echo "ERREUR $nom $version : digest illisible" >&2; exit 1 ;;
  esac
  echo "$REGISTRE/charts/$nom@$digest" >>recopies.txt
  rm -f "$travail"/*.tgz
done <"$liste"

echo "Artefacts à signer :"
cat recopies.txt
