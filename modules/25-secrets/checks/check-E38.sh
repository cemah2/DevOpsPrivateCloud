# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E38.sh — M25-E38 « Panne : MédiAgenda perd sa base » (recette) : le rôle mediagenda-api-recette
# a ses durées de plateforme/secrets (1 h, 24 h) et un identifiant vit plus longtemps qu'un cycle de
# rafraîchissement d'ESO (marge de 10 min pour Reloader) ; l'ExternalSecret mediagenda-db-api est Ready
# et rafraîchi depuis moins d'un cycle (+ 5 min) ; au moins un bail est actif ; aucune
# CiliumNetworkPolicy de mediagenda-recette ne refuse 10.10.20.21-23 sur 5432 et la politique qui les
# autorise est intacte ; /pret répond 200 ; règles d'audit du ruler de Loki (échecs d'identifiants
# dynamiques, révocations en masse) ; journal INC-5238.
# Lecture seule : bao_api (rôle, baux), kube (ExternalSecret, CiliumNetworkPolicy), curl, Loki, GitLab.
# Sourçable par check-E43.sh : variables et fonctions préfixées _m25x_e38_.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E38 — Panne : MédiAgenda perd sa base"
require_cmd curl jq kubectl
_m25p_connexion

# _m25x_e38_secondes DURÉE — durée Go (« 30m », « 1h30m0s ») ou nombre de secondes → secondes.
_m25x_e38_secondes() {
  local d="$1" n=0
  [[ "$d" =~ ^[0-9]+$ ]] && { echo "$d"; return; }
  [[ "$d" =~ ([0-9]+)h ]] && n=$((n + BASH_REMATCH[1] * 3600))
  [[ "$d" =~ ([0-9]+)m([0-9]|s|$) ]] && n=$((n + BASH_REMATCH[1] * 60))
  [[ "$d" =~ ([0-9]+)s$ ]] && [[ ! "$d" =~ ms$ ]] && n=$((n + BASH_REMATCH[1]))
  echo "$n"
}

# _m25x_e38_ip_dans IP CIDR — l'adresse appartient au bloc.
_m25x_e38_ip_dans() {
  local ip="$1" res="${2%/*}" lg="${2#*/}" a b c d x y masque
  [[ "$2" == */* ]] || lg=32
  IFS=. read -r a b c d <<<"$ip"; x=$(((a << 24) | (b << 16) | (c << 8) | d))
  IFS=. read -r a b c d <<<"$res"; y=$(((a << 24) | (b << 16) | (c << 8) | d))
  ((lg >= 0 && lg <= 32)) || return 1
  masque=$(((0xFFFFFFFF << (32 - lg)) & 0xFFFFFFFF))
  (((x & masque) == (y & masque)))
}

# --- Coffre ---------------------------------------------------------------------------------------------
_m25x_e38_role="$(_m25p_bao db-mediagenda/roles/mediagenda-api-recette)"
check_cmd "rôle mediagenda-api-recette : default_ttl 1 h et max_ttl 24 h (valeurs de plateforme/secrets)" \
  _m25p_jq "$_m25x_e38_role" '.data.default_ttl == 3600 and .data.max_ttl == 86400'

_m25x_e38_es="$(kube get externalsecrets.external-secrets.io mediagenda-db-api -n mediagenda-recette -o json 2>/dev/null || true)"
_m25x_e38_cycle="$(_m25x_e38_secondes "$(jq -r '.spec.refreshInterval // "1h"' <<<"${_m25x_e38_es:-null}" 2>/dev/null || echo 1h)")"
_m25x_e38_vie() {
  local vie
  vie="$(jq -r '[.data.default_ttl, .data.max_ttl] | map(select(. > 0)) | min // 0' <<<"$_m25x_e38_role" 2>/dev/null)" || return 1
  ((_m25x_e38_cycle > 0 && vie >= _m25x_e38_cycle + 600))
}
check_cmd "un identifiant de l'API vit au moins un cycle d'ESO + 10 min (sinon il meurt avant d'être remplacé)" _m25x_e38_vie

_m25x_e38_baux="$(_m25p_bao 'sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette?list=true' | jq -r '.data.keys | length' 2>/dev/null || echo 0)"
check_cmd "au moins un bail mediagenda-api-recette actif (identifiants délivrés à l'API)" \
  test "${_m25x_e38_baux:-0}" -ge 1

# --- ESO -------------------------------------------------------------------------------------------------
_m25x_e38_es_frais() {
  local t
  _m25p_jq "$_m25x_e38_es" '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' || return 1
  t="$(jq -r '.status.refreshTime // empty' <<<"$_m25x_e38_es" 2>/dev/null)" || return 1
  [[ -n "$t" ]] && (($(date +%s) - $(date -d "$t" +%s) <= _m25x_e38_cycle + 300))
}
check_cmd "ExternalSecret mediagenda-db-api (recette) Ready et rafraîchi depuis moins d'un cycle (+ 5 min)" _m25x_e38_es_frais

# --- Réseau ----------------------------------------------------------------------------------------------
_m25x_e38_cnp="$(kube get ciliumnetworkpolicies.cilium.io -n mediagenda-recette -o json 2>/dev/null || echo null)"
# _m25x_e38_sans_refus — aucune règle ingressDeny (5432 ou tous ports) dont un CIDR contient 10.10.20.21-23,
#   ni de refus par entité (world, all, cluster…).
_m25x_e38_sans_refus() {
  local regle cidr ip
  [[ "$_m25x_e38_cnp" != null ]] || return 1
  while IFS= read -r regle; do
    [[ -n "$regle" ]] || continue
    jq -e '(.toPorts // []) | length == 0 or any(.[]?.ports[]?; (.port // "0") == "5432" or (.port // "0") == "0")' \
      >/dev/null 2>&1 <<<"$regle" || continue
    jq -e '(.fromEntities // []) | length > 0' >/dev/null 2>&1 <<<"$regle" && return 1
    while IFS= read -r cidr; do
      for ip in 10.10.20.21 10.10.20.22 10.10.20.23; do _m25x_e38_ip_dans "$ip" "$cidr" && return 1; done
    done < <(jq -r '(.fromCIDR // [])[], (.fromCIDRSet // [])[].cidr' <<<"$regle" 2>/dev/null)
  done < <(jq -c '.items[]?.spec.ingressDeny[]?' <<<"$_m25x_e38_cnp" 2>/dev/null)
  return 0
}
check_cmd "mediagenda-recette : aucune CiliumNetworkPolicy ne refuse vault01-03 (10.10.20.21-23) sur 5432" _m25x_e38_sans_refus
check_cmd "mediagenda-recette : mediagenda-db-depuis-openbao ouvre toujours 5432 à 10.10.20.21-23" \
  _m25p_jq "$_m25x_e38_cnp" '
  [.items[] | select(.metadata.name == "mediagenda-db-depuis-openbao") | .spec.ingress[]?
   | select(any(.toPorts[]?.ports[]?; .port == "5432")) | .fromCIDR[]?] | sort
  == ["10.10.20.21/32", "10.10.20.22/32", "10.10.20.23/32"]'

# --- Application -----------------------------------------------------------------------------------------
_m25x_e38_pret="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" \
  https://mediagenda-recette.apps.par1.medisphere.internal/pret 2>/dev/null || true)"
check_cmd "https://mediagenda-recette.apps.par1.medisphere.internal/pret répond 200" test "$_m25x_e38_pret" = 200

# --- Prévention et journal ---------------------------------------------------------------------------------
_m25x_e38_regles="$(curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: audit" -H "Accept: application/json" \
  "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/prometheus/api/v1/rules" 2>/dev/null || echo null)"
for _m25x_e38_r in IdentifiantsDynamiquesEnEchec OpenBaoBauxRevoquesEnMasse; do
  check_cmd "ruler de Loki (audit) : règle $_m25x_e38_r chargée et saine" \
    _m25p_jq "$_m25x_e38_regles" '[.data.groups[]?.rules[]? | select(.name == $n and .health != "err")] | length == 1' \
    --arg n "$_m25x_e38_r"
done
check_cmd "journal de diagnostic INC-5238 sur main (plateforme/medisphere)" _m25x_journal INC-5238
