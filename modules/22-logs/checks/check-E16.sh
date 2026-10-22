# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E16.sh — M22-E16 « Accès, sécurité et sauvegarde des journaux » : politiques réseau de journaux
# (aucune ouverture au monde, écritures des réseaux du lab limitées au push, entrées du cluster limitées),
# Loki toujours joignable depuis MGMT, source audit invisible du Viewer de l'organisation principale,
# versionnage et cycle de vie du compartiment, politique complétée. Lecture seule.

# shellcheck source=_m22-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-production.sh"

title "M22-E16 — Accès, sécurité et sauvegarde des journaux"
require_cmd kubectl jq curl

_m22_e16_cnp="$(kube -n journaux get ciliumnetworkpolicies.cilium.io -o json 2>/dev/null || echo null)"
# Fonctions jq communes : politiques qui sélectionnent Loki (sélecteur vide ou app.kubernetes.io/name=loki)
# et leurs règles d'entrée.
_m22_e16_def='def loki: [.items[] | select((.spec.endpointSelector.matchLabels // {}) as $m
                | ($m | length) == 0 or $m["app.kubernetes.io/name"] == "loki")];
  def entrees: [loki[].spec.ingress[]?];
  def cidrs: ((.fromCIDR // []) + [(.fromCIDRSet // [])[] | .cidr]);
  def espace: ((.matchLabels // {}) | (.["k8s:io.kubernetes.pod.namespace"] // .["io.kubernetes.pod.namespace"] // ""));
  def depuis_alloy: any(.fromEndpoints[]?; ((.matchLabels // {})["app.kubernetes.io/name"] // "") == "alloy");
  def pousse_seulement: ((.toPorts // []) | length > 0)
    and all(.toPorts[]; ((.rules.http // []) | length > 0)
      and all(.rules.http[]; (.method // "") == "POST" and ((.path // "") | test("^\\^?/loki/api/v1/push\\$?$"))));'
_m22_e16_jq() { [[ "$_m22_e16_cnp" != null ]] && jq -e "$_m22_e16_def $1" >/dev/null 2>&1 <<<"$_m22_e16_cnp"; }

if [[ "$_m22_e16_cnp" == null ]]; then
  skip "politiques réseau de journaux" "lecture des CiliumNetworkPolicy impossible pour le compte des checks (wb-checks-reseau, M15-E07)"
else
  check_cmd "au moins une CiliumNetworkPolicy de journaux sélectionne Loki, avec des règles d'entrée" \
    _m22_e16_jq 'entrees | length >= 1'
  check_cmd "aucune règle d'entrée vers Loki ouverte à world, all ou 0.0.0.0/0" \
    _m22_e16_jq '[entrees[] | select(((.fromEntities // []) | any(. == "world" or . == "all")) or (cidrs | any(. == "0.0.0.0/0")))] | length == 0'
  # Toute règle par CIDR qui n'est pas seulement MGMT (10.10.10.0/24) doit être limitée au push.
  check_cmd "écritures venues des réseaux du lab (hors MGMT) limitées à POST /loki/api/v1/push" \
    _m22_e16_jq '[entrees[] | select(cidrs | (length > 0) and any(. != "10.10.10.0/24"))] | (length >= 1) and all(.[]; pousse_seulement)'
  check_cmd "entrées depuis le cluster limitées aux espaces journaux et supervision (aucun sélecteur ouvert)" \
    _m22_e16_jq '([entrees[].fromEndpoints[]? | espace] | all(. == "" or . == "journaux" or . == "supervision"))
      and ([entrees[].fromEndpoints[]? | select((.matchLabels // {}) == {} and (.matchExpressions // []) == [])] | length == 0)'
  check_cmd "Alloy (cluster) n'a que le droit d'écrire : POST /loki/api/v1/push" \
    _m22_e16_jq '[entrees[] | select(depuis_alloy)] | (length >= 1) and all(.[]; pousse_seulement)'
  check_cmd "une politique de sortie encadre Loki (DNS et RGW 10.10.30.200:443 autorisés, rien d'autre en grand)" \
    _m22_e16_jq '[loki[].spec.egress[]?] as $e | ($e | length >= 2)
      and ($e | any((.toCIDR // []) + [(.toCIDRSet // [])[] | .cidr] | any(. == "10.10.30.200/32")))
      and ($e | all(((.toEntities // []) | any(. == "world" or . == "all")) | not))
      and ($e | all(((.toCIDR // []) + [(.toCIDRSet // [])[] | .cidr]) | any(. == "0.0.0.0/0") | not))'
fi

check_cmd "Loki répond toujours depuis MGMT (/ready)" _m22p_pret
_m22_e16_collecte() { (($(_m22p_nb_lignes plateforme '{namespace=~".+"}' 5m) > 0)); }
check_cmd "la collecte continue : des lignes récentes arrivent dans le locataire plateforme" _m22_e16_collecte

if grafana_api health >/dev/null 2>&1 || grafana_api frontend/settings >/dev/null 2>&1; then
  _m22_e16_audit_invisible() {
    local l
    l="$(_m22p_sources_visibles)"
    [[ -n "$l" ]] && ! grep -qx 'Loki — audit' <<<"$l"
  }
  check_cmd "le compte Viewer de l'organisation principale ne voit plus « Loki — audit »" _m22_e16_audit_invisible
  _m22_e16_autres_visibles() { _m22p_sources_visibles | grep -qx 'Loki — mediagenda'; }
  check_cmd "les sources des autres locataires restent visibles (« Loki — mediagenda »)" _m22_e16_autres_visibles
else
  skip "sources Grafana" "API de Grafana injoignable avec le jeton des checks (lab/bin/check 21 05)"
fi

if [[ -r "$_m22p_s3_env" ]] && command -v aws >/dev/null 2>&1; then
  check_output "loki-k8s-par1 : versionnage activé" '"Status": *"Enabled"' _m22p_s3 get-bucket-versioning --bucket "$_m22p_compartiment"
  _m22_e16_cycle() {
    _m22p_s3 get-bucket-lifecycle-configuration --bucket "$_m22p_compartiment" |
      jq -e '[.Rules[] | select(.Status == "Enabled" and (.NoncurrentVersionExpiration.NoncurrentDays // 0) >= 1)] | length >= 1' >/dev/null 2>&1
  }
  check_cmd "loki-k8s-par1 : règle de cycle de vie qui expire les versions non courantes" _m22_e16_cycle
else
  skip "versionnage du compartiment" "aws ou $_m22p_s3_env absent sur ce poste"
fi

check_cmd "politique-journaux.md (main) : sections Accès et Sauvegarde" \
  _m22p_doc docs/observabilite/journaux politique-journaux '^#+ .*Acc[eè]s' '^#+ .*Sauvegarde' 'versionn' 'X-Scope-OrgID'
