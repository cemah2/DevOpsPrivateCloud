# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-S05.sh — F2-S05 : MédiVisio en production, avec ses alertes et son SLO
# À lancer depuis adm01. Lecture seule : cluster (wb-checks : Applications, Deployments, PDB,
# ExternalSecret sans le Secret, SLO Pyrra, PrometheusRule), Alertmanager (configuration active),
# Mailpit (recherche par destinataire), Grafana (recherche de tableaux), GitLab, GET sur la production.

# shellcheck source=_f2-cadre.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-cadre.sh"

title "F2-S05 — MédiVisio en production, avec ses alertes et son SLO"
require_cmd jq curl kubectl

# _f2a_s05_prod_manuelle 'APPS' — les Applications de prod issues du dépôt de déploiement n'ont pas de
# synchronisation automatique.
_f2a_s05_prod_manuelle() {
  jq -e --arg r "/${_F2A_P_DEPLOIEMENT}(\\.git)?$" '[.[] | select((.spec.source.repoURL // .spec.sources[0].repoURL // "") | test($r))] as $a
    | ($a | length) > 0 and all($a[]; (.spec.syncPolicy.automated // null) == null)' >/dev/null 2>&1 <<<"$1"
}
# _f2a_s05_regles_pyrra — chaque SLO de medivisio-prod a sa PrometheusRule du même nom.
_f2a_s05_regles_pyrra() {
  local slo regles
  slo="$(_f2a_k -n medivisio-prod get servicelevelobjectives.pyrra.dev)"
  regles="$(_f2a_k -n medivisio-prod get prometheusrules.monitoring.coreos.com)"
  [[ -n "$slo" && -n "$regles" ]] || return 1
  jq -e --argjson r "$regles" '(.items | length) > 0 and all(.items[]; .metadata.name as $n | any($r.items[]; .metadata.name == $n))' >/dev/null 2>&1 <<<"$slo"
}
# _f2a_s05_runbook — un fichier docs/…runbook… du projet du code parle de retour arrière et de contacts.
_f2a_s05_runbook() {
  local f
  while IFS= read -r f; do
    [[ "$f" =~ runbook ]] || continue
    _f2a_contient "$(_f2a_fichier "$_F2A_P_CODE" "$f")" "retour arri|rollback" "contact|@medisphere" && return 0
  done < <(_f2a_arbre "$_F2A_P_CODE" docs)
  return 1
}

# --- Production livrée à la main, par Argo CD ----------------------------------------------------------
_f2a_s05_apps="$(_f2a_apps_vers medivisio-prod)"
check_cmd "Argo CD : l'Application qui livre medivisio-prod depuis $_F2A_P_DEPLOIEMENT est Synced et Healthy" \
  _f2a_app_saine medivisio-prod "/${_F2A_P_DEPLOIEMENT}(\\.git)?$"
check_cmd "Argo CD : la production n'est PAS synchronisée automatiquement" _f2a_s05_prod_manuelle "$_f2a_s05_apps"
check_cmd "Argo CD : AppProject medivisio interdit la synchronisation de *-prod le week-end (fenêtre deny)" \
  _f2a_json "$(_f2a_k -n argocd get appprojects.argoproj.io medivisio)" \
  'any(.spec.syncWindows[]?; .kind == "deny" and any(.applications[]?; test("prod")))'

# --- Production robuste ---------------------------------------------------------------------------------
_f2a_s05_d="$(_f2a_deploy medivisio-prod)"
check_cmd "medivisio-prod : au moins deux réplicas, tous prêts et à jour" _f2a_deploy_pret "$_f2a_s05_d" 2
check_cmd "medivisio-prod : classe de priorité medisphere-critique" \
  _f2a_json "$_f2a_s05_d" '.spec.template.spec.priorityClassName == "medisphere-critique"'
check_cmd "medivisio-prod : un PodDisruptionBudget couvre le service" \
  _f2a_json "$(_f2a_k -n medivisio-prod get poddisruptionbudgets)" \
  "any(.items[]; (.spec.minAvailable // 0) != 0 or (.spec.maxUnavailable // \"\") != \"\")"
_f2a_s05_dr="$(_f2a_deploy medivisio-recette)"
check_cmd "production et recette exécutent la MÊME empreinte d'image" bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ \
  "$(_f2a_empreinte "$_f2a_s05_d")" "$(_f2a_empreinte "$_f2a_s05_dr")"
check_cmd "$_F2A_URL_PROD/sante répond 200 depuis adm01" _f2a_url_200 "$_F2A_URL_PROD/sante"

# --- Secrets en libre-service --------------------------------------------------------------------------
_f2a_s05_es="$(_f2a_k -n medivisio-prod get externalsecrets.external-secrets.io)"
check_cmd "medivisio-prod : ExternalSecret(s) synchronisés (Ready)" _f2a_json "$_f2a_s05_es" \
  '(.items | length) > 0 and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "medivisio-prod : les ExternalSecret ne lisent que kv/medivisio/prod/…" _f2a_json "$_f2a_s05_es" \
  '[.items[] | (.spec.data[]?.remoteRef.key), (.spec.dataFrom[]?.extract.key)] as $k
   | ($k | length) > 0 and all($k[]; test("^(kv/)?(data/)?medivisio/prod/"))'

# --- SLO et alertes ---------------------------------------------------------------------------------------
_f2a_s05_slo="$(_f2a_k -n medivisio-prod get servicelevelobjectives.pyrra.dev)"
check_cmd "medivisio-prod : un ServiceLevelObjective (Pyrra) étiqueté pour l'équipe medivisio" _f2a_json "$_f2a_s05_slo" \
  'any(.items[]; (.metadata.labels["pyrra.dev/equipe"] // .metadata.labels["pyrra.dev/team"] // "") == "medivisio")'
check_cmd "medivisio-prod : règles générées par Pyrra (PrometheusRule du même nom que chaque SLO)" _f2a_s05_regles_pyrra
_f2a_s05_am="$(_f2a_am_config)"
check_cmd "Alertmanager : route equipe=medivisio vers medivisio@medisphere.internal (configuration active)" \
  _f2a_route_equipe medivisio "$_f2a_s05_am"
check_cmd "Alertmanager : cette route est limitée aux espaces de medivisio" \
  bash -c 'grep -Eq "namespace *=~? *\"?medivisio-(prod|recette)" <<<"$1"' _ "$_f2a_s05_am"
_f2a_s05_mail="$(mailpit_api "search?query=$(_f2a_enc 'to:medivisio@medisphere.internal')" 2>/dev/null || true)"
check_cmd "Mailpit : au moins une alerte reçue par medivisio@medisphere.internal (test de routage)" \
  _f2a_json "$_f2a_s05_mail" '(.messages_count // .total // 0) > 0'

# --- Tableau de bord et runbook -------------------------------------------------------------------------
check_cmd "Grafana : au moins un tableau de bord dans le dossier medivisio" \
  _f2a_json "$(grafana_api "search?type=dash-db&folderUIDs=medivisio" 2>/dev/null || true)" 'length > 0'
check_cmd "runbook du service dans la documentation de $_F2A_P_CODE (docs/, retour arrière, contacts)" _f2a_s05_runbook
