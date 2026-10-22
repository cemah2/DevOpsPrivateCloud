# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E08.sh — M26-E08 : Falco : installation et premières détections
# À lancer depuis adm01. Lecture seule : Application Argo CD, DaemonSet, Deployment, ConfigMap et espace
# falco par le compte des checks ; événements dans Loki (locataire audit, sept derniers jours) ;
# compteurs de falcosidekick dans Prometheus.

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E08 — Falco : installation et premières détections"
require_cmd jq curl kubectl

# --- 1. Le capteur ---------------------------------------------------------------------------------
check_cmd "Application Argo CD falco : Synced et Healthy" _m26d_app_saine falco
_m26d_e08_ds="$(_m26d_k -n falco get daemonset falco -o json)"
check_cmd "DaemonSet falco : un pod prêt sur chacun des $_M26D_NOEUDS nœuds (nœuds de contrôle compris)" \
  _m26d_json "$_m26d_e08_ds" '.status.desiredNumberScheduled == ($n | tonumber) and .status.numberReady == ($n | tonumber)' \
  --arg n "$_M26D_NOEUDS"
check_cmd "DaemonSet falco : pas de conteneur falcoctl (règles de l'image, aucun téléchargement à l'exécution)" \
  _m26d_json "$_m26d_e08_ds" '[.spec.template.spec | (.containers + (.initContainers // []))[].name | select(startswith("falcoctl"))] | length == 0'
check_output "Configuration de Falco : pilote modern_ebpf" 'kind: *modern_ebpf' \
  _m26d_k -n falco get configmap falco -o 'jsonpath={.data.falco\.yaml}'
check_cmd "Espace falco : toutes les images viennent de Harbor" _m26d_images_harbor falco
check_cmd "falcosidekick : au moins un réplica prêt, image 2.31.1" \
  _m26d_json "$(_m26d_k -n falco get deployment falco-falcosidekick -o json)" \
  '(.status.readyReplicas // 0) >= 1 and (.spec.template.spec.containers[0].image | endswith(":2.31.1"))'
check_cmd "Espace falco : exception Pod Security écrite (annotation medisphere.internal/exception-psa)" \
  _m26d_json "$(_m26d_k get namespace falco -o json)" \
  '((.metadata.annotations // {})["medisphere.internal/exception-psa"] // "") != ""
   and .metadata.labels["pod-security.kubernetes.io/audit"] == "restricted"'

# --- 2. Les détections dans Loki (locataire audit) -------------------------------------------------
check_output "Loki (audit) : événement « Terminal shell in container » étiqueté service=falco (7 jours)" '^[1-9]' \
  _m26d_loki_flux '{service="falco", rule="Terminal shell in container"}'
check_output "Loki (audit) : événement « Read sensitive file untrusted » étiqueté service=falco (7 jours)" '^[1-9]' \
  _m26d_loki_flux '{service="falco", rule="Read sensitive file untrusted"}'

# --- 3. Les livraisons de falcosidekick (compteurs, maximum sur 7 jours : un redémarrage les remet à zéro) --
if [[ -z "$(_m26d_valeur 'count(falcosecurity_falcosidekick_outputs_total)')" ]]; then
  _ko "Prometheus : aucune métrique falcosecurity_falcosidekick_* (ServiceMonitor de falcosidekick avec l'étiquette medisphere.internal/supervision ?)"
else
  check_cmd "falcosidekick → Alertmanager : au moins une alerte livrée sans erreur" _m26d_au_moins \
    'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{destination="alertmanager",status="ok"})[7d:30m])' 1
  check_cmd "falcosidekick → Loki : événements livrés" _m26d_au_moins \
    'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{destination="loki",status="ok"})[7d:30m])' 1
  check_output "falcosidekick : aucune erreur de livraison dans la dernière heure" '^0$' \
    _m26d_valeur 'sum(increase(falcosecurity_falcosidekick_outputs_total{status="error"}[1h])) or vector(0)'
fi

# --- 4. Ménage --------------------------------------------------------------------------------------
_m26d_e08_essais="$(_m26d_k -n wb-essais get pods -o json)"
if [[ -z "$_m26d_e08_essais" ]]; then
  skip "Pod d'essai falco-essai" "pods de wb-essais illisibles"
else
  check_cmd "wb-essais : le pod d'essai falco-essai a été supprimé" \
    _m26d_json "$_m26d_e08_essais" '[.items[] | select(.metadata.name == "falco-essai")] | length == 0'
fi
