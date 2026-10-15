# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M15-E34 « Publier une nouvelle application en temps limité » (à lancer à T4)
# Lecture seule : objets de medidoc-dev (wb-checks), DNS sur dns01 et dns02, requêtes HTTP(S) GET vers
# le nom publié, matrice des flux et feuille de temps sur main (API GitLab). Aucun document n'est déposé.

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E34 — Publier MédiDoc dans medidoc-dev"
require_cmd kubectl jq curl dig
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

_M15_E34_NS=medidoc-dev
_M15_E34_NOM="medidoc-dev.$_M15P_APPS"

title "1-2. Application et Service"
check_cmd "Deployment medidoc : 2 réplicas prêts" _m15p_deploy_pret "$_M15_E34_NS" medidoc 2
check_cmd "Service medidoc : ClusterIP, port 80 nommé http vers le port http des pods" \
  _m15p_jq "$(_m15p_get -n "$_M15_E34_NS" service medidoc)" \
  '.spec.type == "ClusterIP" and any(.spec.ports[]; .port == 80 and .name == "http" and (.targetPort == "http" or .targetPort == 8080))'
check_cmd "le Service a des points de terminaison prêts" \
  _m15p_jq "$(_m15p_get -n "$_M15_E34_NS" endpointslices -l kubernetes.io/service-name=medidoc)" \
  '[.items[].endpoints[]? | select(.conditions.ready == true)] | length >= 2'

title "3. Route"
_M15_E34_RT="$(_m15p_get -n "$_M15_E34_NS" httproute medidoc)"
check_cmd "HTTPRoute medidoc attachée à l'écouteur https de gw-par1, pour $_M15_E34_NOM" \
  _m15p_jq "$_M15_E34_RT" 'any(.spec.parentRefs[]; .name == "gw-par1" and (.namespace // "") == "passerelles" and (.sectionName // "https") == "https")
     and any(.spec.hostnames[]; . == $h)' --arg h "$_M15_E34_NOM"
check_cmd "la route est acceptée par la Gateway" _m15p_condition "$_M15_E34_RT" Accepted
check_cmd "les références de la route sont résolues" _m15p_condition "$_M15_E34_RT" ResolvedRefs
check_cmd "l'espace porte medisphere.fr/exposition=oui" _m15p_ns_label "$_M15_E34_NS" medisphere.fr/exposition oui

title "4. Nom"
for _m15_e34_d in "${_M15P_DNS[@]}"; do
  check_cmd "$_M15_E34_NOM résout vers $_M15P_GW_IP sur $_m15_e34_d" _m15p_resout "$_M15_E34_NOM" "$_M15P_GW_IP" "$_m15_e34_d"
done
_m15_e34_txt() {
  local n r
  for n in "a-$_M15_E34_NOM" "$_M15_E34_NOM"; do
    r="$(dig +short +time=3 +tries=1 "@${_M15P_DNS[0]}" "$n" TXT 2>/dev/null)" || r=""
    grep -q 'external-dns/owner=k8s-par1' <<<"$r" && return 0
  done
  return 1
}
check_cmd "l'enregistrement appartient à ExternalDNS (TXT de propriété owner=k8s-par1)" _m15_e34_txt

title "5. HTTPS"
check_cmd "https://$_M15_E34_NOM/readyz répond 200 (certificat valide pour le nom, racine MédiSphère)" \
  _m15p_https_code "https://$_M15_E34_NOM/readyz" '^200$'
check_cmd "la liste des documents répond (GET /documents)" _m15p_https_code "https://$_M15_E34_NOM/documents?limite=1" '^200$'
check_output "http:// redirige vers https://" '^30[1278] https://' \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time "$WB_TIMEOUT" "http://$_M15_E34_NOM/healthz"

title "6. Politiques"
_M15_E34_NP="$(_m15p_get -n "$_M15_E34_NS" networkpolicies)"
_M15_E34_CNP="$(_m15p_get -n "$_M15_E34_NS" ciliumnetworkpolicies)"
_m15_e34_refus() {
  _m15p_jq "$_M15_E34_NP" 'any(.items[]; .spec.podSelector == {} and (.spec.policyTypes | index("Ingress")) and (.spec.policyTypes | index("Egress"))
       and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)' \
    || _m15p_jq "$_M15_E34_CNP" 'any(.items[]; .spec.endpointSelector == {} and .spec.ingress == [{}] and .spec.egress == [{}])'
}
check_cmd "refus par défaut en entrée ET en sortie pour tout l'espace" _m15_e34_refus
check_cmd "entrée autorisée depuis la Gateway (identité ingress) vers 8080" \
  _m15p_jq "$_M15_E34_CNP" 'any(.items[]; any(.spec.ingress[]?; ((.fromEntities // []) | index("ingress")) and any(.toPorts[]?.ports[]?; .port == "8080")))'
check_cmd "sortie autorisée vers s3-01 en TCP 8333 (par nom ou par adresse)" \
  _m15p_jq "$_M15_E34_CNP" 'any(.items[]; any(.spec.egress[]?;
      (any(.toFQDNs[]?; .matchName == "s3-01.par1.medisphere.internal")
       or any((.toCIDR // [])[]; . == "10.10.20.14/32") or any((.toCIDRSet // [])[]; .cidr == "10.10.20.14/32"))
      and any(.toPorts[]?.ports[]?; .port == "8333")))'
check_cmd "aucune sortie vers Internet (pas de world/all, pas de toFQDNs « * »)" \
  _m15p_jq "$_M15_E34_CNP" 'all(.items[]; all(.spec.egress[]?;
      ((.toEntities // []) | (index("world") or index("all")) | not) and all(.toFQDNs[]?; (.matchPattern // "") != "*")))'
check_cmd "aucune entrée depuis tout le cluster ou le monde (pas de fromEntities all/world/cluster)" \
  _m15p_jq "$_M15_E34_CNP" 'all(.items[]; all(.spec.ingress[]?; ((.fromEntities // []) | (index("world") or index("all") or index("cluster")) | not)))'

title "7. Traçabilité"
check_cmd "la matrice des flux du cluster contient les flux de MédiDoc (s3-01:8333)" \
  _m15p_doc_main docs/kubernetes/reseau/matrice-flux-cluster.md 'medidoc' '8333'
check_cmd "feuille de temps et retour d'expérience : docs/kubernetes/reseau/chrono/E34-medidoc.md" \
  _m15p_doc_main docs/kubernetes/reseau/chrono/E34-medidoc.md 'T0' 'T4' 'retour d.exp[ée]rience'
