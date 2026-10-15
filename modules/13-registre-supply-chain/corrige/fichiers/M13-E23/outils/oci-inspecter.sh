#!/usr/bin/env bash
# outils/oci-inspecter.sh — plateforme/outils (M13-E23, PLAT-1437). L'API de distribution OCI à la main :
# défi, jeton, manifeste (négociation de type), digest recalculé, configuration, référents.
# Lecture seule. Identité : HARBOR_USER / HARBOR_PASSWORD dans l'environnement (jamais en argument).
#
#   admin@adm01:~$ HARBOR_USER='robot$medisphere+ci' HARBOR_PASSWORD="$(…)" ~/src/outils/oci-inspecter.sh medisphere/mediagenda-api v1.4.2
set -euo pipefail
REG="${REG:-registry.par1.medisphere.internal}"
DEPOT="${1:?usage : $0 <projet/dépôt> <étiquette|digest>}"
REF="${2:?usage : $0 <projet/dépôt> <étiquette|digest>}"
: "${HARBOR_USER:?HARBOR_USER manquant}" "${HARBOR_PASSWORD:?HARBOR_PASSWORD manquant}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'

# 1. Défi
defi="$(curl -sI "https://$REG/v2/" | tr -d '\r' | sed -n 's/^[Ww][Ww][Ww]-[Aa]uthenticate: //p')"
realm="$(sed -nE 's/.*realm="([^"]+)".*/\1/p' <<<"$defi")"
service="$(sed -nE 's/.*service="([^"]+)".*/\1/p' <<<"$defi")"
echo "défi : realm=$realm service=$service"

# 2. Jeton (identifiants par descripteur)
jeton="$(curl -sf -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") \
  "$realm?service=$service&scope=repository:$DEPOT:pull" | jq -r .token)"
charge="$(cut -d. -f2 <<<"$jeton" | tr '_-' '/+')"
while ((${#charge} % 4)); do charge="$charge="; done
echo "jeton : $(base64 -d <<<"$charge" 2>/dev/null | jq -c '{iss, exp, access}')"
H=(-H "Authorization: Bearer $jeton")

# 3. Manifeste, corps BRUT
curl -sf "${H[@]}" -H "Accept: $ACCEPT" -D "$T/entetes" -o "$T/manifeste" "https://$REG/v2/$DEPOT/manifests/$REF"
type="$(tr -d '\r' <"$T/entetes" | sed -n 's/^[Cc]ontent-[Tt]ype: //p')"
annonce="$(tr -d '\r' <"$T/entetes" | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')"
calcule="sha256:$(sha256sum "$T/manifeste" | cut -d' ' -f1)"
echo "manifeste : $type"
echo "digest annoncé : $annonce"
echo "digest recalculé : $calcule  $([[ "$annonce" == "$calcule" ]] && echo '(identique)' || echo '(DIFFÉRENT)')"
echo "après reformatage (jq .) : sha256:$(jq . "$T/manifeste" | sha256sum | cut -d' ' -f1)  (autres octets, autre digest)"

# 4. Index → manifeste linux/amd64, puis configuration
m="$T/manifeste"
if [[ "$type" == *index* || "$type" == *list* ]]; then
  d="$(jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' "$m" | head -n 1)"
  curl -sf "${H[@]}" -H "Accept: $ACCEPT" -o "$T/plateforme" "https://$REG/v2/$DEPOT/manifests/$d"
  m="$T/plateforme"
  echo "linux/amd64 : $d"
fi
cfg="$(jq -r .config.digest "$m")"
curl -sfL "${H[@]}" -o "$T/config" "https://$REG/v2/$DEPOT/blobs/$cfg"
echo "configuration $cfg : $(jq -c '{user: .config.User, cmd: (.config.Entrypoint // []) + (.config.Cmd // []), labels: .config.Labels}' "$T/config")"

# 5. Référents (OCI 1.1) du digest de l'étiquette
curl -sf "${H[@]}" -H 'Accept: application/vnd.oci.image.index.v1+json' \
  "https://$REG/v2/$DEPOT/referrers/$annonce" | jq -r '.manifests[]? | "référent : \(.artifactType)  \(.digest)"'
