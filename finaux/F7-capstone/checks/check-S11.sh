# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S11.sh — F7-S11 « Panne : la démonstration sous incidents » : instance de production du client
# saine (API, publication, cache, base, accès des agents par le courtier), aucune injection active ni à
# venir, charge de démonstration passée, compte rendu de la journée de jeu. Lecture seule (l'état local
# de la panne est seulement lu).

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S11 — Panne : la démonstration sous incidents"
require_cmd curl jq kubectl

_f7_s11_etat="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F7-S11"

# --- L'instance de production ----------------------------------------------------------------------
check_output "$_f7l_url_prod/pret répond 200" '^200$' _f7l_code "$_f7l_url_prod/pret"
if _f7l_api_repond; then
  _f7_s11_api() { (($(_f7l_api_pretes "$_f7l_ns_prod") >= 2)); }
  check_cmd "$_f7l_ns_prod : au moins deux pods prêts de l'API" _f7_s11_api
  check_cmd "Application de $_f7l_ns_prod Synced/Healthy (aucune modification en direct restée en place)" \
    _f7l_app_saine "$_f7l_ns_prod"
  _f7_s11_pas_de_refus() {
    kube -n "$_f7l_ns_prod" get ciliumnetworkpolicies.cilium.io -o json 2>/dev/null |
      jq -e '[.items[] | select((.spec.egressDeny // []) | length > 0)] | length == 0' >/dev/null 2>&1
  }
  check_cmd "$_f7l_ns_prod : aucune politique réseau n'interdit de sortie à l'API (egressDeny)" _f7_s11_pas_de_refus
  # Le port visé par la route publique existe sur le Service visé.
  _f7_s11_route() {
    local r svc port
    r="$(kube -n "$_f7l_ns_prod" get httproutes.gateway.networking.k8s.io mediagenda -o json 2>/dev/null)" || return 1
    svc="$(jq -r '.spec.rules[0].backendRefs[0].name // empty' <<<"$r")"
    port="$(jq -r '.spec.rules[0].backendRefs[0].port // empty' <<<"$r")"
    [[ -n "$svc" && -n "$port" ]] || return 1
    kube -n "$_f7l_ns_prod" get service "$svc" -o json 2>/dev/null | jq -e --argjson p "$port" 'any(.spec.ports[]; .port == $p)' >/dev/null 2>&1 &&
      jq -e 'any(.status.parents[]?.conditions[]?; .type == "ResolvedRefs" and .status == "True")' >/dev/null 2>&1 <<<"$r"
  }
  check_cmd "route publique « mediagenda » : backend résolu (port existant sur son Service)" _f7_s11_route
  _f7_s11_cache() {
    kube -n "$_f7l_ns_prod" get statefulsets -o json 2>/dev/null | jq -e '
      [.items[] | select(.metadata.name == "valkey" or (.metadata.labels["app.kubernetes.io/name"] // "") == "valkey")]
      | length > 0 and all(.[]; (.spec.replicas // 0) >= 1 and (.status.readyReplicas // 0) == .spec.replicas)' >/dev/null 2>&1
  }
  check_cmd "$_f7l_ns_prod : cache Valkey démarré et prêt" _f7_s11_cache
  _f7_s11_mandataire() {
    kube -n "$_f7l_ns_prod" get configmaps -o json 2>/dev/null |
      jq -e '[.items[] | (.data // {}) | to_entries[] | select(.value | test("extra_jwt_issuers"))] as $c
        | ($c | length) == 0 or all($c[]; .value | test("extra_jwt_issuers[^\n]*-v2\"") | not)' >/dev/null 2>&1
  }
  check_cmd "mandataire du DPI : audience attendue des jetons non altérée" _f7_s11_mandataire
else
  _ko "contrôles Kubernetes de $_f7l_ns_prod : impossibles, l'API de k8s-par1 ne répond pas au compte des checks (kube)"
fi
_f7_s11_agents() {
  local h
  h="$(curl -s -o /dev/null -D - --max-time "$((WB_TIMEOUT * 2))" "$_f7l_url_agents/" 2>/dev/null)" || return 1
  grep -Eq '^HTTP/[0-9.]+ 30[27]' <<<"$h" && grep -Eqi '^location:.*/realms/' <<<"$h"
}
check_cmd "accès des agents : redirection vers l'authentification (mandataire en marche)" _f7_s11_agents
_f7_s11_mappeur() {
  local m
  m="$(_f7l_idp_mappeurs)"
  [[ -n "$m" ]] || return 1
  jq -e --arg g "$_f7l_groupe_idp" 'any(.[]; ((.config.claims // "[]") | fromjson? // [] | any(.[]; .value == $g))
    or ((.config["claim.value"] // "") == $g))' >/dev/null 2>&1 <<<"$m"
}
check_cmd "fournisseur $_f7l_idp : le mappeur des agents attend le groupe convenu « $_f7l_groupe_idp »" _f7_s11_mappeur

# --- Plus aucune injection ---------------------------------------------------------------------------
_f7_s11_meneur_arrete() {
  local pid
  [[ -f "$_f7_s11_etat/meneur.pid" ]] || return 0
  pid="$(<"$_f7_s11_etat/meneur.pid")"
  ! { [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; }
}
check_cmd "aucune injection à venir (meneur de jeu de F7-S11 arrêté)" _f7_s11_meneur_arrete

# --- La journée de jeu a eu lieu ------------------------------------------------------------------------
check_cmd "charge de démonstration passée (séries k6 testid=demo-ghsv… dans Prometheus, 7 derniers jours)" \
  _f7l_prom_positif 'count(count_over_time(k6_http_reqs_total{testid=~"demo-ghsv.*"}[7d]))'
_f7_s11_cr() {
  local f
  while IFS= read -r f; do
    [[ "${f##*/}" =~ ghsv.*\.md$ ]] || continue
    _f7l_contient "$_f7l_doc_projet" "$f" 'chronolog' 'secondes|minutes' 'action' 'incident' && return 0
  done < <(_f7c_arbre "$_f7l_doc_projet" docs/qualite/journees-de-jeu)
  return 1
}
check_cmd "compte rendu docs/qualite/journees-de-jeu/…ghsv….md (chronologie, indisponibilité chiffrée, actions)" _f7_s11_cr
