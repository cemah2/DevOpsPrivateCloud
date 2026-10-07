# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($n, $a… sont des variables jq)
#
# check-E10.sh — M06-E10 : L'API NetBox : jetons, REST et GraphQL
# À lancer depuis adm01. Lecture seule : uniquement des GET (et une requête GraphQL, en lecture).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E10 — L'API NetBox : jetons, REST et GraphQL"
require_cmd curl jq

_m06o_auto="$_M06O_CFG/netbox-auto.token"
_m06o_checks="${WB_NETBOX_TOKEN_FILE:-$_M06O_CFG/netbox-checks.token}"

_m06o_format_v2() {
  [[ "$(wc -l <"$_m06o_auto")" -le 1 ]] && grep -Eq '^nbt_[A-Za-z0-9]+\.[A-Za-z0-9]+$' "$_m06o_auto"
}
_m06o_utilisateur() { _m06o_nb "$_m06o_auto" authentication-check/ | jq -r .username; }
_m06o_nb_vms_socle() { _m06o_nb "$_m06o_auto" 'virtualization/virtual-machines/?tag=socle&brief=true&limit=1' | jq -r .count; }
# Code HTTP vu depuis dns01 avec le jeton d'écriture (en-tête transmis par l'entrée standard).
_m06o_depuis_dns01() {
  printf 'Authorization: Bearer %s\n' "$(tr -d '\n' <"$_m06o_auto")" \
    | remote dns01 "curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H @- $_M06O_NB/api/status/" 2>/dev/null || true
}
_m06o_essai_supprime() { _m06o_nb "$_m06o_checks" 'extras/tags/?slug=essai-api' | jq -r .count; }
_m06o_registre() { grep -qi 'svc-automatisation' "${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md"; }

# --- Fichier du jeton d'écriture --------------------------------------------------------------
check_cmd "netbox-auto.token présent, en mode 600" _m06o_mode600 "$_m06o_auto"
check_cmd "netbox-auto.token contient un jeton v2 (nbt_<clé>.<jeton>), une seule ligne" _m06o_format_v2

# --- Le compte de service -------------------------------------------------------------------------
check_output "le jeton d'écriture authentifie svc-automatisation" '^svc-automatisation$' _m06o_utilisateur
check_output "svc-automatisation ne peut pas lire la liste des utilisateurs (droits minimaux)" '^403$' \
  _m06o_nb_code "$_m06o_auto" users/users/
check_output "svc-automatisation lit les VMs du socle" '^[1-9][0-9]*$' _m06o_nb_vms_socle

# --- Restrictions du jeton (vues par le jeton lui-même : sans permission sur users | token, un compte
# ne voit que ses propres jetons, DEFAULT_PERMISSIONS de NetBox) ----------------------------------
_m06o_jetons="$(_m06o_nb "$_m06o_auto" users/tokens/ 2>/dev/null || true)"
check_cmd "le compte a un jeton d'écriture qui expire" \
  jq -e '[.results[] | select(.write_enabled == true and .expires != null)] | length > 0' <<<"$_m06o_jetons"
check_cmd "le jeton d'écriture est restreint aux adresses de adm01 et runner01 (rien de plus large qu'un /24)" \
  jq -e '[.results[] | select(.write_enabled == true)
          | (.allowed_ips // [] | map(tostring) | join(" ")) as $a
          | select(($a | test("10\\.10\\.10\\.10")) and ($a | test("10\\.10\\.20\\.15"))
                   and ($a | test("/(0|8|16)( |$)") | not))] | length > 0' <<<"$_m06o_jetons"
check_output "depuis dns01, le jeton d'écriture est refusé (adresse non autorisée)" '^(401|403)$' _m06o_depuis_dns01

# --- Jeton des checks : lecture seule -----------------------------------------------------------
check_cmd "le jeton des checks est en lecture seule (write_enabled = false)" _m06o_jeton_lecture_seule "$_m06o_checks"

# --- GraphQL ----------------------------------------------------------------------------------------
_m06o_gql="$(_m06o_graphql '{ virtual_machine_list(filters: {tags: {slug: {exact: "socle"}}}) { name primary_ip4 { address } } }' || true)"
check_cmd "GraphQL : les VMs du socle avec leur IP primaire (dns01 → 10.10.20.10)" \
  jq -e '.data.virtual_machine_list | map(select(.name == "dns01" and (.primary_ip4.address | startswith("10.10.20.10/")))) | length == 1' <<<"$_m06o_gql"

# --- Ménage et traçabilité -----------------------------------------------------------------------------
check_output "l'étiquette d'essai essai-api a été supprimée" '^0$' _m06o_essai_supprime
check_cmd "registre des secrets : jeton NetBox de svc-automatisation inscrit" _m06o_registre
