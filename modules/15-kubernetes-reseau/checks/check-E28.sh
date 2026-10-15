# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E28.sh — M15-E28 « Segmenter un cluster multi-équipes »
# Lecture seule : labels des espaces, CiliumClusterwideNetworkPolicies et CiliumNetworkPolicies
# (wb-checks), politiques et fiche sur main (API GitLab).

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E28 — Segmenter un cluster multi-équipes"
require_cmd kubectl jq curl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Équipes"
check_cmd "mediagenda-dev porte medisphere.fr/equipe=mediagenda" _m15p_ns_label mediagenda-dev medisphere.fr/equipe mediagenda
check_cmd "mediagenda-recette porte medisphere.fr/equipe=mediagenda" _m15p_ns_label mediagenda-recette medisphere.fr/equipe mediagenda
check_cmd "medidoc-dev porte medisphere.fr/equipe=medidoc" _m15p_ns_label medidoc-dev medisphere.fr/equipe medidoc

_M15_E28_CCNP="$(_m15p_get ciliumclusterwidenetworkpolicies)"

title "Proxy DNS de base"
check_cmd "une politique de cluster intercepte le DNS (règle DNS L7) sans refus par défaut" \
  _m15p_jq "$_M15_E28_CCNP" 'any(.items[];
     .spec.enableDefaultDeny.ingress == false and .spec.enableDefaultDeny.egress == false
     and any(.spec.egress[]?; any(.toPorts[]?; (.rules.dns // []) | length > 0)))'
check_cmd "aucune politique de cluster ne met tout le cluster en refus par défaut (endpointSelector vide sans enableDefaultDeny)" \
  _m15p_jq "$_M15_E28_CCNP" 'all(.items[];
     ((.spec.endpointSelector // {"x":1}) != {}) or ((.spec.enableDefaultDeny.ingress == false) and (.spec.enableDefaultDeny.egress == false)))'

title "Cloisons (refus)"
for _m15_e28_ns in mediagenda-dev mediagenda-recette medidoc-dev; do
  check_cmd "$_m15_e28_ns : refus en entrée ET en sortie vers les autres espaces d'équipe" \
    _m15p_jq "$_M15_E28_CCNP" 'any(.items[];
       ((.spec.endpointSelector.matchLabels // {}) | to_entries | any((.key | test("io.kubernetes.pod.namespace$")) and .value == $ns))
       and any(.spec.ingressDeny[]?; any(.fromEndpoints[]?; tostring | test("namespace.labels.medisphere.fr/equipe")))
       and any(.spec.egressDeny[]?;  any(.toEndpoints[]?;   tostring | test("namespace.labels.medisphere.fr/equipe"))))' \
    --arg ns "$_m15_e28_ns"
done
_m15_e28_pas_ouvert() {
  local j
  j="$(_m15p_get ciliumnetworkpolicies -A)"
  _m15p_jq "$j" '[.items[] | select(.metadata.namespace | test("^(mediagenda-|medidoc-)"))
     | select(any(.spec.ingress[]?; (.fromEntities // []) | index("all")))] | length == 0'
}
check_cmd "aucune politique « tout autoriser » (fromEntities: all) dans les espaces d'équipe" _m15_e28_pas_ouvert

title "Sortie vers Internet"
_m15_e28_fqdn() {
  _m15p_jq "$_M15_E28_CCNP$(_m15p_get ciliumnetworkpolicies -A)" '
    [.[].items[]] as $p
    | any($p[]; any(.spec.egress[]?; any(.toFQDNs[]?; .matchName == "calendrier.api.gouv.fr")))
      and all($p[]; all(.spec.egress[]?; all(.toFQDNs[]?; (.matchPattern // "") != "*")))' -s
}
check_cmd "sortie limitée par toFQDNs à calendrier.api.gouv.fr (et aucune règle toFQDNs « * »)" _m15_e28_fqdn

title "Code et documentation"
check_cmd "plateforme/k8s : composants/reseau/politiques/ non vide sur main" \
  _m15p_arbre_non_vide plateforme/k8s composants/reseau/politiques
check_cmd "docs/kubernetes/reseau/segmentation.md sur main, avec la matrice de tests" \
  _m15p_doc_main docs/kubernetes/reseau/segmentation.md 'matrice' 'attendu' 'obtenu' 'calendrier\.api\.gouv\.fr'
