# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M22-E08 : Alerter sur les journaux
# À lancer depuis adm01. Lecture seule : API du ruler de Loki par locataire (GET
# /prometheus/api/v1/rules), configuration effective (/config), ConfigMaps de règles (« kube »),
# fichiers sur main (GitLab), courriel de l'alerte de test dans Mailpit (recherche).

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E08 — Alerter sur les journaux"
require_cmd jq kubectl curl

# --- 1. Le ruler et sa configuration ------------------------------------------------------------------
_m22o_e08_cfg="$(curl -sf --max-time "$WB_TIMEOUT" "$_M22O_LOKI/config" 2>/dev/null || true)"
check_output "ruler : alertes envoyées à l'Alertmanager du cluster (espace supervision)" \
  'alertmanager_url: .*alertmanager.*supervision' printf '%s' "$_m22o_e08_cfg"
check_output "ruler : règles lues dans un dossier local (alimenté par le sidecar)" 'type: local' printf '%s' "$_m22o_e08_cfg"
check_cmd "ConfigMaps de règles étiquetées loki_rule dans journaux (au moins mediagenda et audit)" _m22o_json \
  "$(_m22o_k get configmaps -n "$_M22O_NS" -l loki_rule -o json)" \
  '[.items[].metadata.annotations["k8s-sidecar-target-directory"] // empty] as $d
   | ($d | index("/rules/mediagenda")) != null and ($d | index("/rules/audit")) != null'
check_cmd "le sidecar n'a pas de ClusterRole (droits limités à l'espace journaux)" _m22o_json \
  "$(_m22o_k get clusterroles -o json)" '[.items[] | select(.metadata.name == "loki-clusterrole")] | length == 0'

# --- 2. Règles chargées et saines, par locataire --------------------------------------------------------
_m22o_e08_med="$(_m22o_regles mediagenda)"
check_cmd "locataire mediagenda : règle MediagendaErreurs5xxRafale chargée, sans erreur d'évaluation" _m22o_json "$_m22o_e08_med" \
  'any(.data.groups[]?.rules[]?; .name == "MediagendaErreurs5xxRafale" and .health == "ok")'
check_cmd "locataire mediagenda : la règle porte gravite et equipe=mediagenda" _m22o_json "$_m22o_e08_med" \
  'any(.data.groups[]?.rules[]?; .name == "MediagendaErreurs5xxRafale" and .labels.equipe == "mediagenda" and (.labels.gravite | test("^(critique|avertissement|info)$")))'
_m22o_e08_aud="$(_m22o_regles audit)"
check_cmd "locataire audit : règle AuditEchecsAuthentification chargée, sans erreur d'évaluation" _m22o_json "$_m22o_e08_aud" \
  'any(.data.groups[]?.rules[]?; .name == "AuditEchecsAuthentification" and .health == "ok" and .labels.equipe == "plateforme")'
check_cmd "cloisonnement : la règle d'audit n'est PAS chargée dans le locataire mediagenda" _m22o_json "$_m22o_e08_med" \
  '[.data.groups[]?.rules[]? | select(.name == "AuditEchecsAuthentification")] | length == 0'
for _m22o_e08_t in "${_M22O_LOCATAIRES[@]}"; do
  _m22o_e08_r="$(_m22o_regles "$_m22o_e08_t")"
  if _m22o_json "$_m22o_e08_r" '(.data.groups | length) > 0'; then
    check_cmd "locataire $_m22o_e08_t : toutes les règles ont runbook_url, gravite et equipe" _m22o_json "$_m22o_e08_r" \
      'all(.data.groups[].rules[] | select(.type == "alerting"); (.annotations.runbook_url // "") != "" and .labels.gravite != null and .labels.equipe != null)'
  fi
done

# --- 3. Le code et l'essai ------------------------------------------------------------------------------
for _m22o_e08_f in loki/regles/mediagenda/alertes.yaml loki/regles/audit/alertes.yaml; do
  check_cmd "plateforme/observabilite (main) : $_m22o_e08_f" _m22o_fichier_main "$_M22O_P_OBS" "$_m22o_e08_f"
done
_m22o_e08_mails="$(_m22o_courriels AuditEchecsAuthentification)"
check_cmd "alerte de test reçue par courriel dans Mailpit (AuditEchecsAuthentification : ${_m22o_e08_mails} message(s))" \
  bash -c '[[ "$1" -ge 1 ]]' _ "$_m22o_e08_mails"
