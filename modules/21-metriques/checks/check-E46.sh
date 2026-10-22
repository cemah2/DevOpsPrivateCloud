# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M21-E46 « Mini-projet : la supervision de MédiSphère v1 »
# Contrôle global de la livraison metriques-v1 (depuis adm01). Lecture seule : vue globale, Alertmanager,
# Grafana (Viewer), Mailpit (lecture), kubectl avec le compte des checks, API GitLab en lecture, SSH +
# sudo -n de consultation sur mon01, pvesh en lecture sur pve01. Rejoue les contrôles clés des paliers
# précédents (E02, E07, E08, E11, E15, E24, E26, E28) puis vérifie l'état de livraison. 3 à 6 minutes.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E46 — La supervision de MédiSphère v1 : contrôle global"
require_cmd jq yq kubectl curl git

# --- 1. Contrôles clés des paliers 1 à 3 -------------------------------------------------------------
_m21_e46_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m21_e46_x in E02 E07 E08 E11 E15 E24 E26 E28; do
  if [[ -f "$_m21_e46_dir/check-$_m21_e46_x.sh" ]]; then
    # shellcheck disable=SC1090  # contrôles des autres paliers, chargés dynamiquement
    source "$_m21_e46_dir/check-$_m21_e46_x.sh"
  else
    skip "contrôle M21-$_m21_e46_x" "script check-$_m21_e46_x.sh absent"
  fi
done

# --- 2. Couverture de la collecte ------------------------------------------------------------------------
title "M21-E46 — 2/6 Tout le lab est collecté"
_m21_e46_jobs="$(prom_api 'label/job/values' 2>/dev/null | jq -r '.data[]?' 2>/dev/null)" || _m21_e46_jobs=""
_m21_e46_job() { grep -Eqi -- "$1" <<<"$_m21_e46_jobs"; }
if [[ -z "$_m21_e46_jobs" ]]; then
  skip "couverture" "la vue globale ne répond pas (lab/bin/check 21 24)"
else
  for _m21_e46_p in 'apiserver' 'kubelet' 'etcd' 'coredns' 'cilium|hubble' 'kube-state-metrics' 'node-exporter|node' \
    'vms' 'ceph' 'haproxy' 'pdns|powerdns|dns' 'gitlab' 'harbor|registre' 'pve|hyperviseurs' 'blackbox|sonde' \
    'mediagenda' 'medidoc' 'thanos'; do
    check_cmd "collecte : au moins un job correspond à « $_m21_e46_p »" _m21_e46_job "$_m21_e46_p"
  done
  check_cmd "aucune cible en échec dans toute la vue globale (up == 0)" _m21x_vide 'up == 0'
  check_cmd "étiquettes posées : equipe et environnement sur les séries de MédiAgenda" \
    _m21x_non_vide 'up{namespace=~"mediagenda-.*",equipe!="",environnement!=""}'
fi

# --- 3. Pile de supervision ----------------------------------------------------------------------------
title "M21-E46 — 3/6 Pile de supervision"
check_cmd "Prometheus : 2 réplicas, sidecar Thanos, rétention locale ≤ 15 j" \
  _m21x_kq '.items[0].spec | (.replicas == 2) and (.thanos != null)
            and ((.retention // "15d") | test("^([0-9]+)d$") and (sub("d$"; "") | tonumber) <= 15)' \
  -n supervision prometheuses.monitoring.coreos.com
check_cmd "Prometheus : ni API d'administration ni récepteur remote write dans le cluster (le M23 l'active)" \
  _m21x_kq '.items[0].spec | ((.enableAdminAPI // false) == false) and ((.enableRemoteWriteReceiver // false) == false)' \
  -n supervision prometheuses.monitoring.coreos.com
check_cmd "Prometheus : volumes sur ceph-rbd" \
  _m21x_kq '.items[0].spec.storage.volumeClaimTemplate.spec.storageClassName == "ceph-rbd"' -n supervision prometheuses.monitoring.coreos.com
for _m21_e46_a in kube-prometheus-stack observabilite; do
  check_cmd "Application Argo CD $_m21_e46_a Synced/Healthy" _m21x_app_ok "$_m21_e46_a"
done
_m21_e46_conf="$(_m21x_am_config_json)" || _m21_e46_conf=""
check_cmd "Alertmanager : récepteurs plateforme-mail, astreinte-mail, mediagenda-mail, medidoc-mail" \
  jq -e '[.receivers[].name] as $r | ["plateforme-mail","astreinte-mail","mediagenda-mail","medidoc-mail"] | all(. as $x | $r | index($x) != null)' <<<"${_m21_e46_conf:-null}"
check_cmd "Alertmanager : routage par equipe et par gravite" \
  jq -e '[.route | .. | objects | .matchers? // empty | .[]] | (any(test("equipe")) and any(test("gravite")))' <<<"${_m21_e46_conf:-null}"
_m21_e46_regles_completes() {
  prom_api 'rules?type=alert' | jq -e '[.data.groups[] | .rules[] | select((.labels.equipe // "") != "")
    | select((.labels.gravite // .labels.severity // "") == "" or (.annotations.runbook_url // "") == "")] | length == 0' >/dev/null
}
# (Les alertes générées par Pyrra portent « severity » : Prometheus la recopie dans « gravite » à
# l'envoi, M21-E27 ; la règle chargée ne montre donc pas encore « gravite ».)
check_cmd "règles d'alerte : gravite et runbook_url sur toutes les alertes qui portent une equipe" _m21_e46_regles_completes
check_cmd "SLO : trois ServiceLevelObjective Pyrra (mediagenda-disponibilite, mediagenda-latence, medidoc-disponibilite)" \
  _m21x_kq '[.items[].metadata.name] as $n | ["mediagenda-disponibilite","mediagenda-latence","medidoc-disponibilite"] | all(. as $x | $n | index($x) != null)' \
  servicelevelobjectives.pyrra.dev -A
_m21_e46_dossiers() {
  grafana_api 'search?type=dash-folder' | jq -e '[.[].title | ascii_downcase] as $t
    | ["plateforme", "mediagenda", "medidoc"] | all(. as $x | $t | any(contains($x)))' >/dev/null
}
check_cmd "Grafana : dossiers des équipes plateforme, mediagenda, medidoc" _m21_e46_dossiers
check_cmd "plateforme/observabilite : pipeline de main vert" _m21x_pipeline_main_vert plateforme/observabilite

# --- 4. Rien de provisoire -------------------------------------------------------------------------------
title "M21-E46 — 4/6 Rien de provisoire"
check_cmd "aucune panne M21 encore marquée active" _m21x_aucune_panne_active
_m21_e46_silences() {
  am_api silences | jq -e '[.[] | select(.status.state == "active")
    | select(((.endsAt | sub("\\.[0-9]+"; "") | fromdateiso8601) - (.startsAt | sub("\\.[0-9]+"; "") | fromdateiso8601)) > 604800)] | length == 0' >/dev/null
}
check_cmd "aucun silence actif de plus de 7 jours" _m21_e46_silences
_m21_e46_vm_env() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
    jq -e '[.[] | select(.vmid >= 2210 and .vmid <= 2219)] | length == 0' >/dev/null 2>&1
}
check_cmd "aucune VM d'environnement du module (2210-2219) ne reste" _m21_e46_vm_env
check_cmd "essai de la chaîne d'alerte des témoins terminé (ConfigMap temoin-etat : essai à 0, ou témoins absents)" \
  bash -c '! kubectl --kubeconfig "$1" -n wb-pannes get configmap temoin-etat -o json 2>/dev/null |
    jq -e "(.data[\"etat.json\"] | fromjson) | (.essai == 1) or ((.cardinalite // \"aucune\") != \"aucune\") or ((.mode_file // \"calme\") != \"calme\")" >/dev/null' \
  _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"

# --- 5. Documentation --------------------------------------------------------------------------------
title "M21-E46 — 5/6 Documentation"
_m21_e46_doc() {
  (cd "$_m21x_depot" 2>/dev/null && git ls-files | grep -Eq -- "$1")
}
check_cmd "ADR-0210 présente et commitée (docs/observabilite/metriques/adr/)" _m21_e46_doc '^docs/observabilite/metriques/adr/ADR-0210[^/]*\.md$'
check_cmd "politique d'alerte (docs/observabilite/metriques/politique-alerte.md)" _m21_e46_doc '^docs/observabilite/metriques/politique-alerte\.md$'
check_cmd "politique de budget d'erreur (docs/observabilite/metriques/politique-budget-erreur.md)" _m21_e46_doc '^docs/observabilite/metriques/politique-budget-erreur\.md$'
for _m21_e46_rb in 210 211 212 213 214 215 216 217 218 219; do
  check_cmd "runbook RB-$_m21_e46_rb présent" _m21_e46_doc "^docs/observabilite/metriques/runbooks/RB-$_m21_e46_rb-[^/]*\\.md$"
done
check_cmd "fiche de livraison docs/observabilite/metriques/supervision-v1.md (ce qui est couvert, ce qui ne l'est pas)" \
  _m21x_doc_contient 'docs/observabilite/metriques/supervision-v1.md' '^#+ .*(non couvert|limites|ne couvre pas)'
check_cmd "matrice des flux : node_exporter (9100) et mon01 documentés" \
  _m21x_doc_contient 'docs/socle/matrice-flux.md' '9100'
check_cmd "post-mortem de l'astreinte (INC-4843) présent" _m21_e46_doc '^docs/kubernetes/post-mortems/.*INC-4843.*\.md$'

# --- 6. Livraison ------------------------------------------------------------------------------------
title "M21-E46 — 6/6 Livraison"
_m21_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/metriques-v1' >/dev/null; }
check_cmd "étiquette metriques-v1 posée sur plateforme/medisphere" _m21_e46_etiquette
check_cmd "dépôt de documentation local sans modification en attente" \
  bash -c 'cd "$1" && [ -z "$(git status --porcelain -- docs/observabilite)" ]' _ "$_m21x_depot"
