# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M19-E37 « Panne : la construction d'image échoue » : buildkitd prêt, certificats émis
# par buildkit-ca, aucune politique de refus vers buildkitd, robot du cache actif, pipeline de main de
# mediagenda/api vert, RB-196, panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E37 — Les images se construisent à nouveau"
require_cmd jq kubectl curl

if _m19x_api_repond; then
  check_cmd "buildkitd : Deployment de l'espace buildkit entièrement disponible" \
    _m19x_kq '[.items[] | select((.status.availableReplicas // 0) >= 1 and (.status.availableReplicas // 0) == (.spec.replicas // 1))] | length >= 1' -n buildkit deploy
  check_cmd "certificats de buildkitd émis par buildkit-ca et prêts (aucun autre émetteur « buildkit-ca-* »)" \
    _m19x_kq '[.items[] | select(.spec.issuerRef.name | startswith("buildkit-ca"))] as $c
              | ($c | length) >= 2 and all($c[]; .spec.issuerRef.name == "buildkit-ca"
                and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' -A certificates.cert-manager.io
  check_cmd "aucune CiliumNetworkPolicy de buildkit ne refuse le trafic venant des jobs (ingressDeny)" \
    _m19x_kq '[.items[] | select(.spec.ingressDeny)] | length == 0' -n buildkit ciliumnetworkpolicies.cilium.io
else
  skip "objets de buildkit" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
_m19_e37_robots="$(harbor_api 'robots?page_size=100' 2>/dev/null)" || _m19_e37_robots=""
if [[ -n "$_m19_e37_robots" ]]; then
  check_cmd "Harbor : robot(s) du cache de construction (plateforme, « cache ») actifs" \
    jq -e '[.[] | select((.name | test("cache"; "i")) and ((.name | startswith("robot$plateforme+")) or any(.permissions[]?; .namespace == "plateforme")))]
           | length >= 1 and all(.[]; .disable | not)' <<<"$_m19_e37_robots"
else
  skip "robots Harbor" "liste des robots non lisible par le robot des checks (droits système requis)"
fi
check_cmd "mediagenda/api : dernier pipeline de main réussi (construction comprise)" _m19x_pipeline_vert mediagenda/api main
check_cmd "RB-196 : section sur la construction par buildkitd (TLS, réseau, registre, stockage)" \
  _m19x_doc_contient 'RB-196*.md' 'buildkit'
check_cmd "panne M19-E37 close (lab/bin/break 19 37 --annuler après réparation)" _m19x_aucune_panne_active E37
