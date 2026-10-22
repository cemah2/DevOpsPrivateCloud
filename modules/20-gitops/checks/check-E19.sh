# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E19.sh — M20-E19 « Notifications d'Argo CD ». Lecture seule : argocd-notifications-cm,
# AppProjects, Applications (wb-checks), messages reçus par Mailpit (mailpit_api).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E19 — Notifications d'Argo CD"
require_cmd jq kubectl curl yq

_e19_cm="$(_m20o_obj argocd configmap argocd-notifications-cm)"
_e19_svc="$(jq -r '.data["service.email"] // ""' <<<"${_e19_cm:-null}" 2>/dev/null | yq -o json -I0 '.' 2>/dev/null)" || _e19_svc=""
check_cmd "service email : smtp.par1.medisphere.internal, port 25" \
  _m20o_jq "$_e19_svc" '.host == "smtp.par1.medisphere.internal" and .port == 25'
check_cmd "service email : vérification TLS conservée (pas d'insecure_skip_verify)" \
  _m20o_jq "$_e19_svc" '(.host // "") != "" and (.insecure_skip_verify // false) == false'
check_cmd "service email : expéditeur dans medisphere.internal" \
  _m20o_jq "$_e19_svc" '(.from // "") | test("@medisphere\\.internal$")'
for _e19_t in on-sync-failed on-health-degraded on-deployed; do
  check_cmd "déclencheur $_e19_t défini" _m20o_jq "$_e19_cm" '.data | has("trigger." + $t)' --arg t "$_e19_t"
done
check_cmd "modèles : au moins trois, avec un sujet de courriel" \
  _m20o_jq "$_e19_cm" '[.data | to_entries[] | select(.key | startswith("template.")) | select(.value | test("subject"))] | length >= 3'
_e19_dep="$(_m20o_obj argocd deployment argocd-notifications-controller)"
check_cmd "contrôleur de notifications : prêt" _m20o_jq "$_e19_dep" '(.status.readyReplicas // 0) >= 1'

_e19_proj="$(_m20o_obj argocd appprojects.argoproj.io mediagenda)"
check_cmd "AppProject mediagenda : abonnement on-sync-failed par courriel" \
  _m20o_jq "$_e19_proj" '.metadata.annotations["notifications.argoproj.io/subscribe.on-sync-failed.email"] // "" | test("@medisphere\\.internal")'
check_cmd "AppProject mediagenda : abonnement on-health-degraded par courriel" \
  _m20o_jq "$_e19_proj" '.metadata.annotations["notifications.argoproj.io/subscribe.on-health-degraded.email"] // "" | test("@medisphere\\.internal")'
_e19_prod="$(_m20o_app mediagenda-prod)"
check_cmd "mediagenda-prod (et elle seule) : abonnement on-deployed" \
  _m20o_jq "$_e19_prod" '.metadata.annotations["notifications.argoproj.io/subscribe.on-deployed.email"] // "" | test("@medisphere\\.internal")'
_e19_rec="$(_m20o_app mediagenda-recette)"
check_cmd "mediagenda-recette : pas d'abonnement on-deployed (bruit)" \
  _m20o_jq "$_e19_rec" '(.metadata.annotations // {}) | has("notifications.argoproj.io/subscribe.on-deployed.email") | not'

_e19_msgs="$(mailpit_api 'search?query=from%3Aargocd%40medisphere.internal' 2>/dev/null || true)"
if [[ -z "$_e19_msgs" ]]; then
  check_cmd "Mailpit : API lisible (identifiants des checks, M19-E03)" false
else
  check_cmd "Mailpit : au moins un message d'Argo CD reçu" _m20o_jq "$_e19_msgs" '(.messages_count // 0) >= 1'
  check_cmd "Mailpit : un message « Échec de synchronisation » (échec provoqué)" \
    _m20o_jq "$_e19_msgs" '[.messages[]? | select(.Subject | test("chec de synchronisation"))] | length >= 1'
  check_cmd "Mailpit : un message de déploiement de la prod" \
    _m20o_jq "$_e19_msgs" '[.messages[]? | select(.Subject | test("mediagenda-prod") and test("ploy"))] | length >= 1'
fi
