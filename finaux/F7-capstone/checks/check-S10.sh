# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F7-S10 « Des engagements de service mesurés » : SLO du client (Pyrra) et leurs règles,
# sonde externe de mon01, outil et pipeline du rapport mensuel, rapport publié, documents, nom global,
# réplique de PAR2 (si un kubeconfig de lecture de k8s-par2 est fourni). Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S10 — Des engagements de service mesurés"
require_cmd curl jq kubectl dig

# --- SLO ---------------------------------------------------------------------------------------------
if _f7l_api_repond; then
  _f7_s10_slos() {
    kube get servicelevelobjectives.pyrra.dev -A -o json 2>/dev/null | jq -r --arg c "$_f7l_client" '
      .items[] | select((.metadata.labels["pyrra.dev/client"] // "") == $c or (.metadata.name | startswith($c + "-")))
      | "\(.metadata.namespace) \(.metadata.name)"'
  }
  _f7_s10_slo_json() { kube get servicelevelobjectives.pyrra.dev -A -o json 2>/dev/null; }
  _f7_s10_nb() { (($(_f7_s10_slos | grep -c .) >= 3)); }
  check_cmd "au moins trois SLO Pyrra pour le client $_f7l_client" _f7_s10_nb
  _f7_s10_sonde() {
    _f7_s10_slo_json | jq -e --arg c "$_f7l_client" 'any(.items[]; (.metadata.name | startswith($c)) and
      ((.spec.indicator | tostring) | test("probe_success")))' >/dev/null 2>&1
  }
  check_cmd "un SLO du client mesure la disponibilité vue des sondes externes (probe_success)" _f7_s10_sonde
  _f7_s10_latence() {
    _f7_s10_slo_json | jq -e --arg c "$_f7l_client" 'any(.items[]; (.metadata.name | startswith($c)) and
      (.spec.indicator.latency != null) and ((.spec.indicator | tostring) | test("le=\\\\\"0.3\\\\\"|le=\\\"0.3\\\"")))' >/dev/null 2>&1
  }
  check_cmd "un SLO du client mesure la latence au seuil du contrat (seau le=\"0.3\")" _f7_s10_latence
  _f7_s10_regles() {
    local ns n ok=0
    while read -r ns n; do
      [[ -n "$n" ]] || continue
      kube -n "$ns" get prometheusrules.monitoring.coreos.com "$n" >/dev/null 2>&1 && ok=$((ok + 1))
    done < <(_f7_s10_slos)
    ((ok >= 3))
  }
  check_cmd "Pyrra a produit les PrometheusRule des SLO du client" _f7_s10_regles
else
  _ko "SLO du client : impossibles, l'API de k8s-par1 ne répond pas au compte des checks (kube)"
fi
check_cmd "témoin de mon01 : une sonde vise ${_f7l_url_prod#https://}" \
  _f7l_prom_positif "count(probe_success{instance=~\".*${_f7l_url_prod#https://}.*\"})" temoin
check_cmd "sonde de ${_f7l_url_prod#https://} fédérée dans le cluster" \
  _f7l_prom_positif "count(probe_success{job=\"blackbox\", instance=~\".*${_f7l_url_prod#https://}.*\"})"

# --- Rapport mensuel -----------------------------------------------------------------------------------
_f7_s10_outil() { _f7l_trouver "$_f7l_outils" bin '^bin/' "$_f7l_client|client" 'disponibilit' 'maintenance' >/dev/null; }
check_cmd "$_f7l_outils (main) : outil de rapport mensuel (disponibilité, maintenances)" _f7_s10_outil
_f7_s10_planifie() {
  gitlab_api "projects/$(_f7c_enc "$_f7l_outils")/pipeline_schedules?scope=active" 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1
}
check_cmd "$_f7l_outils : un pipeline planifié actif" _f7_s10_planifie
check_cmd "rapport docs/capstone/rapports/${_f7l_client}-AAAA-MM.md : disponibilité, incidents, capacité chiffrés" \
  _f7l_doc rapports "^${_f7l_client}-[0-9]{4}-[0-9]{2}\\.md\$" 'disponibilit' 'incident' 'capacit' '[0-9]+[.,][0-9]+ ?%'

# --- Documents ----------------------------------------------------------------------------------------
check_cmd "engagements.md : indicateurs, glissant/calendaire, maintenances annoncées" \
  _f7l_doc . '^engagements\.md$' 'ENF-03' 'ENF-05' 'calendaire' 'maintenance' 'sonde'
check_cmd "pra-ghsv.md : réplication, essai de reprise isolé, RPO et RTO mesurés" \
  _f7l_doc . "^pra-${_f7l_client}\\.md\$" 'RPO' 'RTO' 't(é|e)moin' 'mesur'
check_cmd "RB-374 (rapport mensuel d'un client)" _f7l_doc runbooks '^RB-374' 'maintenance' 'rapport'

# --- Nom global et PAR2 ---------------------------------------------------------------------------------
check_dns "${_f7l_client}.medisphere.internal résout (nom indépendant du site)" "${_f7l_client}.medisphere.internal" A '^[0-9]+\.' 10.10.20.10
_f7_s10_par2() {
  _f7l_par2 -n "$_f7l_ns_prod" get clusters.postgresql.cnpg.io -o json 2>/dev/null | jq -e '
    any(.items[]; (.spec.replica.primary // "") != "" and (.spec.replica.primary != (.spec.replica.self // .metadata.name))
      and ((.status.phase // "") | test("healthy|replica"; "i")))' >/dev/null 2>&1
}
if [[ -r "$_f7l_par2_kc" ]]; then
  check_cmd "k8s-par2 : réplique de la base du client en topologie distribuée, en bonne santé" _f7_s10_par2
else
  skip "réplique de la base du client à PAR2" "WB_F7_PAR2_KUBECONFIG absent ($_f7l_par2_kc)"
fi
