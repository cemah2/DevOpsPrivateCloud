# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E08.sh — M26-E08 : Falco : installation et premières détections
# À lancer depuis adm01. Lecture seule : Application Argo CD, DaemonSet, Deployment, ConfigMap et espace
# falco par le compte des checks ; événements dans Loki (locataire audit, 30 derniers jours, ignoré
# avec la marche à suivre s'il n'y en a aucun) ;
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
# Fenêtre de 30 jours (le locataire audit garde un an ; 720 h reste sous la durée de requête maximale de
# Loki). Sans événement dans la fenêtre (check relancé longtemps après l'exercice), le contrôle est
# IGNORÉ avec la marche à suivre pour en régénérer un, jamais réussi ; Loki illisible = KO.
_M26D_E08_REGEN="régénère : kubectl -n wb-essais run falco-essai --image=registry.par1.medisphere.internal/dockerhub/library/debian:13-slim --restart=Never -- sleep 3600, puis kubectl -n wb-essais exec -it falco-essai -- bash, cat /etc/shadow > /dev/null, exit, kubectl -n wb-essais delete pod falco-essai, et relance le check"
# _m26d_e08_nb 'LogQL' DURÉE — nombre de flux, ou « erreur » si Loki ne répond pas.
_m26d_e08_nb() {
  loki_requete "$1" audit "$2" 2>/dev/null \
    | jq -r 'if .status == "success" then (.data.result | length) else "erreur" end' 2>/dev/null || echo erreur
}
_m26d_e08_evenement() {
  local regle="$1" desc n
  desc="Loki (audit) : événement « $regle » étiqueté service=falco (30 jours)"
  n="$(_m26d_e08_nb "{service=\"falco\", rule=\"$regle\"}" 720h)"
  if [[ "$n" =~ ^[1-9] ]]; then
    _ok "$desc"
  elif [[ "$n" == 0 ]]; then
    skip "$desc" "aucun événement dans les 30 derniers jours ; $_M26D_E08_REGEN"
  else
    _ko "$desc (Loki, locataire audit, ne répond pas)"
  fi
}
_m26d_e08_evenement "Terminal shell in container"
_m26d_e08_evenement "Read sensitive file untrusted"

# --- 3. Les livraisons de falcosidekick (compteurs, maximum sur 7 jours : un redémarrage les remet à zéro) --
# Rien à livrer depuis 7 jours (aucun événement Falco dans Loki, aucune livraison ni erreur de livraison
# sur la même fenêtre) : contrôles des livraisons IGNORÉS, avec la marche à suivre ; une livraison
# en erreur ou un événement non livré restent un KO.
_m26d_e08_recents="$(_m26d_e08_nb '{service="falco"}' 168h)"
if [[ -z "$(_m26d_valeur 'count(falcosecurity_falcosidekick_outputs_total)')" ]]; then
  _ko "Prometheus : aucune métrique falcosecurity_falcosidekick_* (ServiceMonitor de falcosidekick avec l'étiquette medisphere.internal/supervision ?)"
elif [[ "$_m26d_e08_recents" == 0 ]] \
  && ! _m26d_au_moins 'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{status="ok"})[7d:30m])' 1 >/dev/null 2>&1 \
  && ! _m26d_au_moins 'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{status="error"})[7d:30m])' 1 >/dev/null 2>&1; then
  skip "falcosidekick → Alertmanager et Loki : livraisons" "aucun événement Falco depuis 7 jours, rien à livrer ; $_M26D_E08_REGEN"
else
  check_cmd "falcosidekick → Alertmanager : au moins une alerte livrée sans erreur" _m26d_au_moins \
    'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{destination="alertmanager",status="ok"})[7d:30m])' 1
  check_cmd "falcosidekick → Loki : événements livrés" _m26d_au_moins \
    'max_over_time(sum(falcosecurity_falcosidekick_outputs_total{destination="loki",status="ok"})[7d:30m])' 1
fi
if [[ -n "$(_m26d_valeur 'count(falcosecurity_falcosidekick_outputs_total)')" ]]; then
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
