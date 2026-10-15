#!/usr/bin/env bash
# outils/sbom-recherche.sh — plateforme/outils (M13-E18, SEC-1436). Réponse à une alerte : « qui
# contient ce paquet, dans quelle version ? », à partir des SBOM ATTESTÉES (signées par la clé de la CI)
# des images en service, sans relire le code ni réanalyser les images.
#
#   admin@adm01:~$ ~/src/outils/sbom-recherche.sh <paquet> [projet...]     (défaut : medisphere plateforme bibliotheque)
#   ex. : sbom-recherche.sh prometheus-client
# Sortie TSV : projet/dépôt  étiquette  digest  paquet  version  type-de-paquet (purl)  provenance-de-la-preuve
# « non-vérifiée » : pas d'attestation vérifiable (image à traiter à part : SBOM Harbor, réanalyse).
# Authentification : fichier Docker de l'utilisateur (DOCKER_CONFIG ou ~/.docker/config.json), lecture.
# Clé publique : docs/registre/cosign.pub de ta copie de plateforme/medisphere (WB_DEPOT).
set -euo pipefail

REG="registry.par1.medisphere.internal"
PAQUET="${1:?usage : $0 <paquet> [projet...]}"
shift
PROJETS=("$@")
((${#PROJETS[@]})) || PROJETS=(medisphere plateforme bibliotheque)
CLE="${COSIGN_PUB:-${WB_DEPOT:-$HOME/medisphere}/docs/registre/cosign.pub}"
AUTH="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
for o in skopeo cosign jq; do command -v "$o" >/dev/null || { echo "$o requis" >&2; exit 2; }; done
[[ -r "$CLE" ]] || { echo "clé publique illisible : $CLE" >&2; exit 2; }
[[ -r "$AUTH" ]] || { echo "fichier d'authentification absent : $AUTH" >&2; exit 2; }
# Nom normalisé (PEP 503) : « prometheus_client », « Prometheus.Client » → « prometheus-client ».
norm() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[-_.]+/-/g'; }
CIBLE="$(norm "$PAQUET")"

printf 'image\tetiquette\tdigest\tpaquet\tversion\tpurl\tpreuve\n'
for p in "${PROJETS[@]}"; do
  # Dépôts du projet (catalogue Harbor restreint aux administrateurs : on passe par l'API du projet).
  for repo in $(curl -sf -K <(jq -r --arg r "$REG" '.auths[$r].auth | @base64d | "user = \"" + . + "\""' "$AUTH") \
    "https://$REG/api/v2.0/projects/$p/repositories?page_size=100" | jq -r '.[].name'); do
    for t in $(skopeo list-tags --authfile "$AUTH" "docker://$REG/$repo" | jq -r '.Tags[]' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true); do
      d="$(skopeo inspect --authfile "$AUTH" --format '{{.Digest}}' "docker://$REG/$repo:$t")"
      d="${d#sha256:}"
      ref="$REG/$repo@sha256:$d"
      if sbom="$(cosign verify-attestation --key "$CLE" --insecure-ignore-tlog=true --type spdxjson "$ref" 2>/dev/null)"; then
        trouve="$(jq -r --arg c "$CIBLE" '.payload | @base64d | fromjson | .predicate.packages[]?
            | select((.name | ascii_downcase | gsub("[-_.]+"; "-")) == $c)
            | [.name, (.versionInfo // "?"), ([.externalRefs[]? | select(.referenceType == "purl") | .referenceLocator][0] // "")] | @tsv' <<<"$sbom" | sort -u)"
        if [[ -n "$trouve" ]]; then
          while IFS=$'\t' read -r n v u; do
            printf '%s\t%s\tsha256:%s\t%s\t%s\t%s\tSBOM attestée vérifiée\n' "$repo" "$t" "$d" "$n" "$v" "$u"
          done <<<"$trouve"
        fi
      else
        printf '%s\t%s\tsha256:%s\t-\t-\t-\tnon-vérifiée\n' "$repo" "$t" "$d"
      fi
    done
  done
done
