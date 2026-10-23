#!/usr/bin/env bash
# outils/copier-images.sh — copie vers reg02 des dernières versions SIGNÉES des dépôts listés (F5-S04).
# Projet plateforme/copie-par2, lancé par le pipeline planifié sur le runner protégé.
#
# Pour chaque dépôt : les N dernières versions étiquetées v* (API de Harbor), puis pour chacune :
#   1. vérification de la signature avec la clé publique MédiSphère (docs/registre/cosign.pub, copiée
#      dans le dépôt : cosign.pub) — une image non signée ou mal signée N'EST PAS copiée, le job échoue ;
#   2. cosign copy (image, signatures, attestations, SBOM attachés) vers reg02, --force pour la dernière
#      version : son étiquette est réécrite à chaque passage, ce qui sert de battement de cœur
#      (pra_reg02, mesure de l'âge sur reg02, RB-354).
# Les identifiants passent par un fichier de configuration Docker temporaire (jamais en argument).
set -Eeuo pipefail
umask 077

liste="${1:?usage : $0 liste-images.yaml}"
harbor=registry.par1.medisphere.internal
reg02=reg02.par2.medisphere.internal
cle="${COSIGN_CLE_PUBLIQUE:-cosign.pub}"
: "${HARBOR_ROBOT_USER:?}" "${HARBOR_ROBOT_PASSWORD:?}" "${REG02_USER:?}" "${REG02_PASSWORD:?}"
for c in cosign jq curl yq; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done
[[ -r "$cle" ]] || { echo "clé publique illisible : $cle" >&2; exit 2; }

DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
jq -n --arg h "$harbor" --arg ha "$(printf '%s:%s' "$HARBOR_ROBOT_USER" "$HARBOR_ROBOT_PASSWORD" | base64 -w0)" \
      --arg r "$reg02" --arg ra "$(printf '%s:%s' "$REG02_USER" "$REG02_PASSWORD" | base64 -w0)" \
      '{auths: {($h): {auth: $ha}, ($r): {auth: $ra}}}' >"$DOCKER_CONFIG/config.json"

n="$(yq '.versions' "$liste")"
echecs=0

# versions DEPOT → étiquettes v* les plus récentes (API Harbor v2.0, tri par date de poussée).
versions() {
  local projet="${1%%/*}" depot="${1#*/}"
  curl -sf --max-time 30 -K <(printf 'user = "%s:%s"\n' "$HARBOR_ROBOT_USER" "$HARBOR_ROBOT_PASSWORD") \
    "https://$harbor/api/v2.0/projects/$projet/repositories/$(jq -rn --arg s "$depot" '$s|@uri|@uri')/artifacts?with_tag=true&sort=-push_time&page_size=50" \
    | jq -r --argjson n "$n" '[.[] | .tags[]?.name | select(startswith("v"))] | .[:$n][]'
}

copier() {
  local depot="$1" tag="$2" force="$3"
  local src="$harbor/$depot:$tag" dst="$reg02/$depot:$tag"
  if ! cosign verify --key "$cle" --insecure-ignore-tlog=true "$src" >/dev/null; then
    echo "REFUS : $src — signature absente ou invalide, non copiée" >&2
    return 1
  fi
  if [[ "$force" == oui ]]; then
    cosign copy --force "$src" "$dst"
  else
    cosign copy "$src" "$dst"
  fi
  # Contrôle à l'arrivée : même empreinte, signature vérifiable SUR reg02.
  cosign verify --key "$cle" --insecure-ignore-tlog=true "$dst" >/dev/null
  echo "copié : $depot:$tag"
}

while IFS= read -r depot; do
  premiere=oui
  mapfile -t tags < <(versions "$depot")
  ((${#tags[@]})) || { echo "aucune version v* pour $depot" >&2; echecs=$((echecs + 1)); continue; }
  for t in "${tags[@]}"; do
    copier "$depot" "$t" "$premiere" || echecs=$((echecs + 1))
    premiere=non
  done
done < <(yq '.depots[], .charts[]' "$liste")

if ((echecs)); then echo "$echecs copie(s) en échec" >&2; exit 1; fi
