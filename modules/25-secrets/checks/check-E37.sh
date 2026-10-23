# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E37.sh — M25-E37 « Panne : un ExternalSecret en erreur » : en recette, le SecretStore openbao
# est conforme au dépôt (KV v2, montage kv, méthode k8s-par1, rôle eso-mediagenda-recette, compte eso,
# audience openbao.medisphere.internal) et prêt ; le rôle eso-mediagenda-recette d'OpenBao attend la
# même audience ; aucune CiliumNetworkPolicy ne refuse la sortie d'ESO vers le coffre ; aucun magasin
# du cluster n'est en erreur ; les ExternalSecret de mediagenda-recette sont synchronisés (harbor-pull
# depuis moins de 70 min) ; une alerte sur les ExternalSecret en erreur est chargée ; journal INC-5237.
# Lecture seule : kube (compte des checks : objets d'ESO et de Cilium, jamais de Secret), bao_api
# (configuration du rôle), Prometheus (règles chargées), GitLab (journal).

# shellcheck source=_m25-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert-b.sh"

title "M25-E37 — Panne : un ExternalSecret en erreur"
require_cmd kubectl curl jq
_m25p_connexion

_M25Y_E37_NS=mediagenda-recette
_M25Y_E37_AUD=openbao.medisphere.internal

_m25y_e37_ss="$(kube -n "$_M25Y_E37_NS" get secretstores.external-secrets.io openbao -o json 2>/dev/null || echo null)"
check_cmd "SecretStore openbao (recette) : KV v2, montage kv, méthode k8s-par1" \
  _m25p_jq "$_m25y_e37_ss" '.spec.provider.vault | .version == "v2" and .path == "kv" and .auth.kubernetes.mountPath == "k8s-par1"'
check_cmd "SecretStore openbao (recette) : rôle eso-mediagenda-recette, compte eso, audience $_M25Y_E37_AUD" \
  _m25p_jq "$_m25y_e37_ss" '.spec.provider.vault.auth.kubernetes
    | .role == "eso-mediagenda-recette" and .serviceAccountRef.name == "eso"
      and ((.serviceAccountRef.audiences // []) | index($a) != null)' --arg a "$_M25Y_E37_AUD"
check_cmd "SecretStore openbao (recette) : prêt (Ready=True, le contrôleur s'y connecte)" \
  _m25p_jq "$_m25y_e37_ss" '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0'

_m25y_e37_role="$(_m25p_bao auth/k8s-par1/role/eso-mediagenda-recette)"
if [[ "$_m25y_e37_role" == null ]]; then
  skip "OpenBao : rôle eso-mediagenda-recette" "illisible par wb-checks : lecture des rôles de k8s-par1 absente de sa politique ?"
else
  check_cmd "OpenBao : rôle eso-mediagenda-recette (audience $_M25Y_E37_AUD, compte eso de mediagenda-recette)" \
    _m25p_jq "$_m25y_e37_role" '.data | .audience == $a and .bound_service_account_names == ["eso"]
      and .bound_service_account_namespaces == ["mediagenda-recette"]' --arg a "$_M25Y_E37_AUD"
fi

# Aucun refus de sortie qui touche ESO et le port 8200 (CNP de l'espace d'ESO, CCNP du cluster).
_m25y_e37_cnp="$(kube -n external-secrets get ciliumnetworkpolicies.cilium.io -o json 2>/dev/null || echo null)"
check_cmd "espace external-secrets : aucune CiliumNetworkPolicy avec egressDeny (sorties d'ESO non refusées)" \
  _m25p_jq "$_m25y_e37_cnp" '[.items[] | select((.spec.egressDeny // []) | length > 0)] | length == 0'
_m25y_e37_ccnp="$(kube get ciliumclusterwidenetworkpolicies.cilium.io -o json 2>/dev/null || echo null)"
if [[ "$_m25y_e37_ccnp" == null ]]; then
  skip "aucune CiliumClusterwideNetworkPolicy ne refuse le port 8200 en sortie" "objets illisibles par le compte des checks"
else
  check_cmd "aucune CiliumClusterwideNetworkPolicy ne refuse le port 8200 en sortie" \
    _m25p_jq "$_m25y_e37_ccnp" '[.items[] | .spec.egressDeny[]? | .toPorts[]?.ports[]? | select(.port == "8200")] | length == 0'
fi

_m25y_e37_css="$(kube get clustersecretstores.external-secrets.io -o json 2>/dev/null || echo null)"
_m25y_e37_ssa="$(kube get secretstores.external-secrets.io -A -o json 2>/dev/null || echo null)"
_m25y_e37_magasins_prets() {
  [[ "$_m25y_e37_css" != null && "$_m25y_e37_ssa" != null ]] || return 1
  jq -se '[.[].items[] | select(([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) == 0)]
          | length == 0' >/dev/null 2>&1 <<<"$_m25y_e37_css $_m25y_e37_ssa"
}
check_cmd "aucun SecretStore ni ClusterSecretStore du cluster en erreur" _m25y_e37_magasins_prets

_m25y_e37_es="$(kube -n "$_M25Y_E37_NS" get externalsecrets.external-secrets.io -o json 2>/dev/null || echo null)"
check_cmd "ExternalSecret de mediagenda-recette : tous synchronisés (Ready=True, SecretSynced)" \
  _m25p_jq "$_m25y_e37_es" '(.items | length > 0) and all(.items[];
    [.status.conditions[]? | select(.type == "Ready" and .status == "True" and .reason == "SecretSynced")] | length > 0)'
check_cmd "ExternalSecret harbor-pull : synchronisé depuis moins de 70 min" \
  _m25p_jq "$_m25y_e37_es" '[.items[] | select(.metadata.name == "harbor-pull")
    | .status.refreshTime // "" | select(. != "") | sub("\\.[0-9]+"; "") | fromdateiso8601
    | select(now - . < 4200)] | length == 1'

check_cmd "Prometheus : alerte chargée sur les ExternalSecret en erreur (externalsecret_status_condition)" \
  _m25y_regle_presente 'externalsecret_status_condition'
check_cmd "journal de diagnostic INC-5237 sur main (plateforme/medisphere)" _m25y_journal INC-5237
