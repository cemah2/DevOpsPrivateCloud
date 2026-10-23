# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M25-E14 « Identifiants dynamiques PostgreSQL pour MédiAgenda ».
# Vérifie : moteur db-mediagenda/ de type database, connexions recette (10.10.41.64, certificat
# vérifié) et prod (10.10.41.65), rôles api et migrateur (TTL 1 h, max 24 h, appartenance au bon
# rôle de groupe, objets possédés par mediagenda), Service LoadBalancer et politique réseau de la
# recette, générateurs et ExternalSecret de la recette, bail actif, API de recette prête, observations.
# Lecture seule : bao_api (configuration des connexions et rôles, liste des baux), kube, curl, ~/m25/e14/.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E14 — Identifiants dynamiques PostgreSQL pour MédiAgenda"
require_cmd jq kubectl curl

check_cmd "moteur db-mediagenda/ monté, de type database" _m25o_moteur_type db-mediagenda database

# _m25o_e14_connexion ENV ADRESSE — greffon PostgreSQL, adresse du LoadBalancer, TLS vérifié, rôles permis.
_m25o_e14_connexion() {
  _m25o_json "$(_m25o_bao "db-mediagenda/config/mediagenda-$1")" --arg env "$1" --arg ip "$2" '
    .data.plugin_name == "postgresql-database-plugin"
    and (.data.connection_details.connection_url | contains("@" + $ip + ":5432/mediagenda"))
    and (.data.connection_details.connection_url | test("sslmode=verify-(ca|full)"))
    and (.data.connection_details.username == "openbao")
    and ((.data.allowed_roles | sort) == (["mediagenda-api-" + $env, "mediagenda-migrateur-" + $env] | sort))'
}
check_cmd "connexion mediagenda-recette : 10.10.41.64, compte openbao, certificat vérifié, deux rôles permis" \
  _m25o_e14_connexion recette 10.10.41.64
check_cmd "connexion mediagenda-prod : 10.10.41.65, compte openbao, certificat vérifié, deux rôles permis" \
  _m25o_e14_connexion prod 10.10.41.65
check_cmd "connexion mediagenda-recette : politique de mot de passe déclarée" \
  _m25o_json "$(_m25o_bao db-mediagenda/config/mediagenda-recette)" '(.data.password_policy // "") != ""'

# _m25o_e14_role NOM 'regex création' ['regex interdite'] — TTL 1 h, max 24 h, connexion, instructions.
_m25o_e14_role() {
  _m25o_json "$(_m25o_bao "db-mediagenda/roles/$1")" --arg re "$2" --arg non "${3:-^\$}" '
    .data.default_ttl == 3600 and .data.max_ttl == 86400
    and (.data.creation_statements | join(" ") | test($re; "i"))
    and (.data.creation_statements | join(" ") | test("VALID UNTIL"; "i"))
    and (.data.creation_statements | join(" ") | test("SUPERUSER|CREATEROLE|CREATEDB"; "i") | not)
    and (.data.creation_statements | join(" ") | test($non; "i") | not)
    and ((.data.revocation_statements // []) | join(" ") | test("DROP ROLE"; "i"))'
}
for _m25o_e14_env in recette prod; do
  check_cmd "rôle mediagenda-api-$_m25o_e14_env : 1 h / 24 h, membre de mediagenda_api (pas du propriétaire), révoqué par DROP ROLE" \
    _m25o_e14_role "mediagenda-api-$_m25o_e14_env" 'IN ROLE "?mediagenda_api"?' 'IN ROLE[^;]*\bmediagenda\b"?([^_]|$)'
  check_cmd "rôle mediagenda-migrateur-$_m25o_e14_env : 1 h / 24 h, objets créés au nom de mediagenda" \
    _m25o_e14_role "mediagenda-migrateur-$_m25o_e14_env" "SET +role *(=|TO) *'?\"?mediagenda'?\"?"
done

# --- Exposition de la base de recette --------------------------------------------------------------
_m25o_e14_svc="$(_m25o_k get services -n mediagenda-recette -o json)"
check_cmd "recette : Service LoadBalancer 10.10.41.64:5432 vers le primaire (externalTrafficPolicy Local)" \
  _m25o_json "$_m25o_e14_svc" '
  any(.items[]; .spec.type == "LoadBalancer" and (.status.loadBalancer.ingress[0].ip // "") == "10.10.41.64"
      and .spec.externalTrafficPolicy == "Local" and any(.spec.ports[]; .port == 5432)
      and (.spec.selector["cnpg.io/instanceRole"] // .spec.selector.role // "") == "primary")'
check_cmd "recette : port 5432 ouvert aux seuls 10.10.20.21-23 (CiliumNetworkPolicy)" \
  _m25o_json "$(_m25o_k get ciliumnetworkpolicies.cilium.io -n mediagenda-recette -o json)" '
  any(.items[]; [.spec.ingress[]? | select(any(.toPorts[]?.ports[]?; .port == "5432")) | .fromCIDR[]?]
      | (length > 0) and all(test("^10\\.10\\.20\\.2[1-3]/32$")))'
check_cmd "recette : Cluster mediagenda-db déclare les rôles openbao (CREATEROLE, sans SUPERUSER) et mediagenda_api" \
  _m25o_json "$(_m25o_k get clusters.postgresql.cnpg.io mediagenda-db -n mediagenda-recette -o json)" '
  [.spec.managed.roles[]?] as $r
  | any($r[]; .name == "openbao" and .createrole == true and (.superuser // false) == false and (.inherit // true) == false)
    and any($r[]; .name == "mediagenda_api" and (.login // false) == false)'

# --- ESO en recette --------------------------------------------------------------------------------
check_cmd "recette : générateurs VaultDynamicSecret mediagenda-api et mediagenda-migrateur (chemins creds de recette)" \
  _m25o_json "$(_m25o_k get vaultdynamicsecrets.generators.external-secrets.io -n mediagenda-recette -o json)" '
  [.items[] | {n: .metadata.name, p: .spec.path}] as $g
  | any($g[]; .n == "mediagenda-api" and (.p | test("db-mediagenda/creds/mediagenda-api-recette$")))
    and any($g[]; .n == "mediagenda-migrateur" and (.p | test("db-mediagenda/creds/mediagenda-migrateur-recette$")))'
for _m25o_e14_es in mediagenda-db-api mediagenda-db-migrateur; do
  check_cmd "recette : ExternalSecret $_m25o_e14_es Ready" _m25o_es_pret mediagenda-recette "$_m25o_e14_es"
done
check_cmd "recette : au moins un bail mediagenda-api-recette actif" \
  bash -c '[[ "$1" -ge 1 ]]' _ "$(_m25o_baux db-mediagenda/creds/mediagenda-api-recette)"
check_cmd "recette : l'API ne lit plus mediagenda-db-app (Deployment)" \
  _m25o_json "$(_m25o_k get deployment mediagenda -n mediagenda-recette -o json)" '
  [.spec.template.spec.containers[].env[]? | select(.name == "MEDIAGENDA_DB_URL") | .valueFrom.secretKeyRef.name]
  == ["mediagenda-db-api"]'
check_cmd "https://mediagenda-recette.apps.par1.medisphere.internal/pret répond 200" \
  bash -c '[[ "$1" == 200 ]]' _ "$(_m25o_http https://mediagenda-recette.apps.par1.medisphere.internal/pret)"

# --- Observations ----------------------------------------------------------------------------------
check_cmd "m25/e14/banc.md : sort d'une session à la révocation du bail" _m25o_local e14/banc.md 'r[ée]voqu'
check_cmd "m25/e14/observations.md : propriétaire des tables du migrateur et refus du DROP par l'API" \
  _m25o_local e14/observations.md 'must be owner|propri[ée]taire'
check_cmd "docs/securite/secrets/identifiants-dynamiques.md sur main" \
  _m25o_fichier "$_M25O_P_DOC" "$_M25O_DOC_SECRETS/identifiants-dynamiques.md"
