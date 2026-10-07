#!/usr/bin/env bash
# essais-api.sh — M06-E10, étapes 4 à 6 rejouables : lectures REST, écriture avec If-Match,
# journal des changements, nettoyage. À lancer sur adm01.
# Les jetons sont lus dans des FICHIERS (jamais sur la ligne de commande : ps les montrerait).
set -euo pipefail

NB="${NETBOX_URL:-https://nbx01.par1.medisphere.internal}/api"
AUTO="$HOME/.config/workbook/netbox-auto.token"
CHECKS="${WB_NETBOX_TOKEN_FILE:-$HOME/.config/workbook/netbox-checks.token}"

# nb FICHIER_JETON MÉTHODE CHEMIN [ARGS curl…] — appel authentifié ; l'en-tête est passé à curl
# par un descripteur de fichier (-H @-) pour que le jeton n'apparaisse pas dans ps.
nb() {
  local jeton="$1" methode="$2" chemin="$3"
  shift 3
  printf 'Authorization: Bearer %s\n' "$(<"$jeton")" \
    | curl -sS -X "$methode" -H @- -H 'Accept: application/json' "$@" "$NB/$chemin"
}

echo "== qui suis-je"
nb "$AUTO" GET authentication-check/ | jq -r .username

echo "== VMs du socle : nom, statut, IP primaire (fields=)"
nb "$AUTO" GET 'virtualization/virtual-machines/?tag=socle&fields=name,status,primary_ip4' \
  | jq -r '.results[] | [.name, .status.value, (.primary_ip4.address // "-")] | @tsv'

echo "== adresses du préfixe INFRA"
nb "$AUTO" GET 'ipam/ip-addresses/?parent=10.10.20.0/24&limit=1' | jq .count

echo "== pagination : limit=2, en suivant next"
page="virtualization/virtual-machines/?tag=socle&brief=true&limit=2"
while [[ -n "$page" ]]; do
  reponse="$(nb "$AUTO" GET "$page")"
  jq -r '.results[].name' <<<"$reponse"
  suivant="$(jq -r '.next // empty' <<<"$reponse")"
  page="${suivant#"$NB/"}"
done

echo "== écriture : étiquette essai-api, puis deux PATCH avec le MÊME ETag"
id="$(nb "$AUTO" POST extras/tags/ -H 'Content-Type: application/json' \
  --data '{"name": "essai-api", "slug": "essai-api", "description": "M06-E10"}' | jq -r .id)"
etag="$(nb "$AUTO" GET "extras/tags/$id/" -D - -o /dev/null | sed -n 's/^[Ee][Tt]ag: *//p' | tr -d '\r')"
echo "ETag lu : $etag"
for essai in 1 2; do
  code="$(nb "$AUTO" PATCH "extras/tags/$id/" -H 'Content-Type: application/json' -H "If-Match: $etag" \
    --data "{\"description\": \"M06-E10, modification $essai\"}" -o /dev/null -w '%{http_code}')"
  echo "PATCH $essai : HTTP $code"     # attendu : 200 puis 412 (Precondition Failed)
done

echo "== journal des changements de svc-automatisation"
nb "$AUTO" GET 'core/object-changes/?user_name=svc-automatisation&limit=5' \
  | jq -r '.results[] | [.time, .action.value, .changed_object_type, (.object_repr // "")] | @tsv'

echo "== nettoyage"
nb "$AUTO" DELETE "extras/tags/$id/" -o /dev/null -w 'DELETE : HTTP %{http_code}\n'

echo "== le jeton des checks est-il en lecture seule ? (lecture de ses propres propriétés)"
nb "$CHECKS" GET users/tokens/ | jq '.results[] | {description, write_enabled, expires}'
