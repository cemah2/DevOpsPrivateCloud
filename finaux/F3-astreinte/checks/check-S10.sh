# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F3-S10 « Jeudi : les secrets ne suivent plus » (INC-5910) : la VIP du coffre est
# portée par le seul nœud actif, les trois nœuds sont en service, le rôle eso-mediagenda-recette et sa
# politique sont ceux de plateforme/secrets, les clients de recette passent par la VIP, l'ExternalSecret
# des identifiants dynamiques est prêt et frais, MédiAgenda (recette) est prêt ; trace de l'incident.
# Lecture seule : sys/health sans jeton, bao_api (métadonnées), kube, SSH de lecture (ip addr).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S10 — Les secrets suivent de nouveau (INC-5910)"
require_cmd curl jq kubectl ssh

_f3s_sante

# --- Coffre ----------------------------------------------------------------------------------------------
_s10_vip='https://openbao.par1.medisphere.internal:8200'
_s10_vip_active() {
  bao_api sys/health 2>/dev/null | jq -e '.initialized == true and .sealed == false and .standby == false' >/dev/null 2>&1
}
check_cmd "la VIP du coffre ($_s10_vip) répond : nœud actif, descellé" _s10_vip_active

_s10_grappe() {
  local n c actifs=0 attente=0
  for n in vault01 vault02 vault03; do
    c="$(_f3f_bao_noeud "$n")"
    case "$c" in 200) actifs=$((actifs + 1)) ;; 429) attente=$((attente + 1)) ;; esac
  done
  ((actifs == 1 && attente == 2))
}
check_cmd "vault01-03 en service : un nœud actif, deux en attente" _s10_grappe

_s10_un_porteur() {
  local n c=0
  for n in vault01 vault02 vault03; do
    if _f3f_ssh "$n" "ip -o -4 addr show" | grep -q ' 10\.10\.20\.200/'; then c=$((c + 1)); fi
  done
  ((c == 1))
}
check_cmd "la VIP 10.10.20.200 est portée par un seul nœud (keepalived actif)" _s10_un_porteur

_s10_role="$(bao_api auth/k8s-par1/role/eso-mediagenda-recette 2>/dev/null || true)"
check_cmd "rôle k8s-par1 eso-mediagenda-recette : politique eso-mediagenda-recette seule, espace et compte inchangés" \
  _f3f_json "$_s10_role" '(.data.token_policies == ["eso-mediagenda-recette"])
    and (.data.bound_service_account_namespaces == ["mediagenda-recette"])
    and (.data.bound_service_account_names == ["eso"])'
_s10_pol="$(bao_api sys/policies/acl/eso-mediagenda-recette 2>/dev/null | jq -r '.data.policy // empty' 2>/dev/null || true)"
check_cmd "politique eso-mediagenda-recette : lecture de db-mediagenda/creds/mediagenda-api-recette" \
  grep -q 'db-mediagenda/creds/mediagenda-api-recette' <<<"$_s10_pol"

# --- Clients de recette -----------------------------------------------------------------------------------
_s10_ss="$(_f3f_k -n mediagenda-recette get secretstores.external-secrets.io openbao -o json)"
check_cmd "SecretStore openbao (mediagenda-recette) : adresse de la VIP, prêt" \
  _f3f_json "$_s10_ss" '.spec.provider.vault.server == $v and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0)' \
  --arg v "$_s10_vip"
_s10_gen="$(_f3f_k -n mediagenda-recette get vaultdynamicsecrets.generators.external-secrets.io -o json)"
check_cmd "générateurs VaultDynamicSecret de mediagenda-recette : tous par la VIP" \
  _f3f_json "$_s10_gen" '(.items | length) >= 1 and all(.items[]; .spec.provider.server == $v)' --arg v "$_s10_vip"

_s10_es="$(_f3f_k -n mediagenda-recette get externalsecrets.external-secrets.io mediagenda-db-api -o json)"
_s10_es_frais() {
  local t cycle
  _f3f_condition "$_s10_es" Ready || return 1
  cycle="$(_f3f_secondes "$(jq -r '.spec.refreshInterval // "1h"' <<<"$_s10_es" 2>/dev/null || echo 1h)")"
  t="$(jq -r '.status.refreshTime // empty' <<<"$_s10_es" 2>/dev/null)" || return 1
  [[ -n "$t" ]] && (($(date +%s) - $(date -d "$t" +%s) <= cycle + 300))
}
check_cmd "ExternalSecret mediagenda-db-api (recette) Ready et rafraîchi depuis moins d'un cycle (+ 5 min)" _s10_es_frais
check_cmd "MédiAgenda recette : $_f3f_recette/pret répond 200" test "$(_f3f_code "$_f3f_recette/pret")" = 200

# --- Trace -----------------------------------------------------------------------------------------------
check_cmd "RB-336 publié (docs/exploitation/runbooks/)" _f3f_rb_present RB-336
_f3s_trace INC-5910 2
