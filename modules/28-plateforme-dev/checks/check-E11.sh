# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M28-E11 : Revue : l'autoscaling et le locataire du stagiaire
# Lecture seule : compte rendu de revue (GitLab, GET) ; objets du cluster : la proposition n'est pas appliquée.

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E11 — Revue : l'autoscaling et le locataire du stagiaire"
require_cmd jq kubectl curl

_M28D_E11="$(_m28d_fichier plateforme/medisphere docs/plateforme-dev/revue-autoscaling-lucas.md 2>/dev/null || true)"
_m28d_e11_lignes="$(grep -Ec '^\|[[:space:]]*[0-9]+[[:space:]]*\|' <<<"$_M28D_E11" || true)"
check_cmd "plateforme/medisphere : docs/plateforme-dev/revue-autoscaling-lucas.md présent" test -n "$_M28D_E11"
check_cmd "au moins 10 constats numérotés dans le tableau de revue (${_m28d_e11_lignes:-0})" test "${_m28d_e11_lignes:-0}" -ge 10
check_cmd "des constats classés bloquants" grep -Eqi 'bloquant' <<<"$_M28D_E11"
for _m28d_e11_m in 'v2beta2|autoscaling/v2' 'Rollout' 'VPA' 'clair|Secret' 'cluster-admin' 'minReplicaCount|zéro|zero' \
  'User|personne' 'quota|budget' 'AMQP|5672|droits'; do
  check_cmd "la revue traite : $_m28d_e11_m" grep -Eqi -- "$_m28d_e11_m" <<<"$_M28D_E11"
done
check_cmd "pas de Tenant « partenaire » dans le cluster" _m28d_absent tenants.capsule.clastix.io partenaire
check_cmd "mediagenda-prod : l'HPA vise toujours le Rollout (pas le Deployment)" _m28d_kq \
  '.spec.scaleTargetRef.kind == "Rollout"' -n mediagenda-prod horizontalpodautoscalers.autoscaling mediagenda
check_cmd "mediagenda-prod : aucun VPA actif" _m28d_kq \
  '[.items[] | select((.spec.updatePolicy.updateMode // "Recreate") != "Off")] | length == 0' \
  -n mediagenda-prod verticalpodautoscalers.autoscaling.k8s.io
check_cmd "medinotif-prod : aucun ScaledObject à zéro ni en AMQP" _m28d_kq \
  '[.items[] | select((.spec.minReplicaCount // 0) == 0 or ([.spec.triggers[]? | select((.metadata.protocol // "") == "amqp")] | length > 0))] | length == 0' \
  -n medinotif-prod scaledobjects.keda.sh
