# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
#
# check-E07.sh — M23-E07 : L'auto-instrumentation par l'opérateur, en comparaison
# Lecture seule : Instrumentation et pods de wb-essais (kube), recherches TraceQL dans Tempo (7 jours :
# l'essai peut être retiré avant la vérification), comparatif dans plateforme/medisphere (GitLab, GET).

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E07 — L'auto-instrumentation par l'opérateur, en comparaison"
require_cmd jq kubectl curl

check_cmd "l'essai a produit des traces (service mediagenda-essai-auto, 7 jours)" _m23d_traces 604800 \
  '{ resource.service.name = "mediagenda-essai-auto" }'
check_cmd "spans PostgreSQL de l'essai, sans une ligne de code (7 jours)" _m23d_traces 604800 \
  '{ resource.service.name = "mediagenda-essai-auto" && (span.db.system.name = "postgresql" || span.db.system = "postgresql") }'

if _m23d_kq '.metadata.name == "python-essai"' -n wb-essais instrumentations.opentelemetry.io python-essai; then
  check_cmd "Instrumentation python-essai : image d'auto-instrumentation tirée de Harbor" _m23d_kq \
    '.spec.python.image | test("^registry\\.par1\\.medisphere\\.internal/")' -n wb-essais instrumentations.opentelemetry.io python-essai
  check_cmd "pod de la copie : conteneur d'initialisation injecté par l'opérateur" _m23d_kq \
    '[.items[] | select([.spec.initContainers[]?.name] | index("opentelemetry-auto-instrumentation-python") != null)] | length >= 1' \
    -n wb-essais pods -l app.kubernetes.io/name=mediagenda-auto
else
  skip "Instrumentation et pod injecté dans wb-essais" "essai déjà retiré : les traces ci-dessus en font foi"
fi
check_cmd "aucune Instrumentation hors de wb-essais (jamais en dev, recette, prod)" _m23d_kq \
  '[.items[] | select(.metadata.namespace != "wb-essais")] | length == 0' instrumentations.opentelemetry.io -A
_m23o_e07_sans_injection() {
  _m23d_kq '[.items[] | select(.metadata.namespace | test("^(mediagenda|medidoc)-")) | select([(.spec.template.metadata.annotations // {}) | keys[] | select(startswith("instrumentation.opentelemetry.io/inject"))] | length > 0)] | length == 0' \
    deployments -A
}
check_cmd "aucune annotation d'injection sur les Deployments des espaces applicatifs" _m23o_e07_sans_injection
check_cmd "plateforme/medisphere : auto-instrumentation.md (comparaison, double instrumentation, décision)" \
  _m23d_contient plateforme/medisphere docs/observabilite/traces/auto-instrumentation.md 'double' 'd[ée]cision' 'm[ée]moire|surco[uû]t'
