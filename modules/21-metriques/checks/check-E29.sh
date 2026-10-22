# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M21-E29 « Sécuriser la pile de supervision »
# À lancer depuis adm01. Lecture seule : ConfigMap de configuration de Grafana, CR Prometheus,
# espaces, politiques Cilium, PrometheusRule et RoleBindings (compte wb-checks), règles chargées
# (Thanos Query), requêtes HTTP ANONYMES vers Grafana (aucun identifiant envoyé), GitLab.

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E29 — Sécuriser la pile de supervision"
require_cmd kubectl jq curl

title "Grafana"
_m21_e29_ini="$(kube -n "$_M21P_NS" get configmap kps-grafana -o jsonpath='{.data.grafana\.ini}' 2>/dev/null || true)"
# _m21_e29_cle SECTION CLE VALEUR — grafana.ini rendu par le chart contient « cle = valeur » dans [section].
_m21_e29_cle() {
  awk -v s="[$1]" -v k="$2" -v v="$3" '
    /^\[/ { dans = ($0 == s) }
    dans && $0 ~ "^"k"[[:space:]]*=" { sub("^[^=]*=[[:space:]]*", ""); if ($0 == v) trouve = 1 }
    END { exit !trouve }' <<<"$_m21_e29_ini"
}
check_cmd "inscription libre désactivée (users.allow_sign_up = false)" _m21_e29_cle users allow_sign_up false
check_cmd "accès anonyme désactivé (auth.anonymous.enabled = false)" _m21_e29_cle auth.anonymous enabled false
check_cmd "cookies de session réservés à HTTPS (security.cookie_secure = true)" _m21_e29_cle security cookie_secure true
check_cmd "politique de mots de passe des comptes locaux (auth.basic.password_policy = true)" _m21_e29_cle auth.basic password_policy true
check_cmd "instantanés publics interdits (snapshots.external_enabled = false)" _m21_e29_cle snapshots external_enabled false
check_cmd "durée de session bornée (auth.login_maximum_lifetime_duration)" \
  grep -Eq '^login_maximum_lifetime_duration[[:space:]]*=[[:space:]]*[0-9]+[mhd]' <<<"$_m21_e29_ini"
check_http "Grafana refuse une recherche anonyme (/api/search → 401)" \
  "${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}/api/search" 401

title "Prometheus : API d'administration et règles par équipe"
_m21_e29_p="$(_m21p_prometheus)"
check_cmd "API d'administration désactivée dans le cluster (enableAdminAPI absent ou false)" \
  _m21p_jq "$_m21_e29_p" '(.spec.enableAdminAPI // false) == false'
check_cmd "étiquette d'espace imposée aux objets des équipes (enforcedNamespaceLabel: namespace)" \
  _m21p_jq "$_m21_e29_p" '.spec.enforcedNamespaceLabel == "namespace"'
check_cmd "objets de la plateforme (supervision) exemptés : règles et ServiceMonitor" _m21p_jq "$_m21_e29_p" '
  any(.spec.excludedFromEnforcement[]?; .namespace == "supervision" and .resource == "prometheusrules")
  and any(.spec.excludedFromEnforcement[]?; .namespace == "supervision" and .resource == "servicemonitors")'
check_cmd "les règles ne sont lues que dans des espaces choisis (ruleNamespaceSelector non vide)" \
  _m21p_jq "$_m21_e29_p" '(.spec.ruleNamespaceSelector // {}) | (.matchLabels // {} | length) + (.matchExpressions // [] | length) > 0'
_m21_e29_sel="$(jq -r '.spec.ruleNamespaceSelector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$_m21_e29_p" 2>/dev/null || true)"
if [[ -n "$_m21_e29_sel" ]]; then
  for _m21_e29_ns in supervision mediagenda-prod; do
    check_output "l'espace $_m21_e29_ns est sélectionné ($_m21_e29_sel)" "^$_m21_e29_ns\$" \
      kube get namespaces -l "$_m21_e29_sel" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  done
fi
_m21_e29_rr="$(_m21p_regles alert)"
check_cmd "une règle d'équipe de mediagenda-prod est chargée, bornée à son espace par l'opérateur" _m21p_jq "$_m21_e29_rr" '
  any(.data.groups[]; (.file | test("mediagenda-prod-")) and any(.rules[]; .query | test("namespace=\"mediagenda-prod\"")))'
check_cmd "la plateforme garde ses règles globales (Watchdog chargée)" _m21p_alerte_chargee Watchdog "$_m21_e29_rr"
_m21_e29_rb="$(_m21p_json -n mediagenda-prod get rolebindings)"
check_cmd "l'équipe MédiAgenda LIT règles et moniteurs de mediagenda-prod (RoleBinding vers un rôle de lecture)" \
  _m21p_jq "$_m21_e29_rb" 'any(.items[]; any(.subjects[]?; .name == "medisphere:mediagenda-devs") and (.roleRef.name | test("supervision")))'

title "Réseau de l'espace supervision"
_m21_e29_cnp="$(_m21p_json -n "$_M21P_NS" get ciliumnetworkpolicies.cilium.io)"
check_cmd "refus par défaut en entrée pour tout l'espace" _m21p_jq "$_m21_e29_cnp" '
  any(.items[]; (.spec.endpointSelector // {}) == {} and ((.spec.ingress // []) == [{}]))'
check_cmd "refus par défaut en sortie pour tout l'espace" _m21p_jq "$_m21_e29_cnp" '
  any(.items[]; (.spec.endpointSelector // {}) == {} and ((.spec.egress // []) == [{}]))'
check_cmd "Grafana a son autorisation d'entrée (Gateway)" _m21p_jq "$_m21_e29_cnp" '
  any(.items[]; .spec.endpointSelector.matchLabels["app.kubernetes.io/name"] == "grafana"
      and any(.spec.ingress[]?; (.fromEntities // []) | index("ingress")))'
# Le cloisonnement ne doit rien avoir cassé : lecture, collecte, envoi des blocs, notifications.
check_output "après cloisonnement : Thanos Query voit toujours 2 sidecars et le Store" '^ok$' \
  bash -c 'jq -e "([.data.sidecar[]?|select(.lastError==null)]|length)==2 and ([.data.store[]?|select(.lastError==null)]|length)>=1" >/dev/null <<<"$1" && echo ok' _ \
  "$(prom_api stores 2>/dev/null || echo null)"
check_output "après cloisonnement : aucune cible du cluster en échec de collecte dans supervision" '^0$' \
  _m21p_valeur 'count(up{namespace="supervision"} == 0) or vector(0)'
check_output "après cloisonnement : Alertmanager notifie sans échec depuis 1 h" '^0$' \
  _m21p_valeur 'sum(increase(alertmanager_notifications_failed_total{namespace="supervision"}[1h])) or vector(0)'

title "Documentation"
check_cmd "mesures de sécurité écrites (docs/observabilite/metriques/securite.md ou équivalent)" \
  _m21p_doc_present "$_M21P_DOC" docs/observabilite/metriques 'secur[^/]*\.md$' 15
skip "rotation du mot de passe admin de Grafana" "non vérifiable sans le mot de passe : auto-évaluation (corrigé)"
