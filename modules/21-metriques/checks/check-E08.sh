# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E08.sh — M21-E08 : Superviser les VMs : node_exporter partout
# À lancer depuis adm01. Lecture seule : API de Prometheus, « kube » (ScrapeConfig), API GitLab,
# GET HTTPS sur node_exporter de quelques hôtes depuis adm01 (MGMT joint tout le lab).

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E08 — Superviser les VMs : node_exporter partout"
require_cmd jq curl kubectl

# --- 1. Le code --------------------------------------------------------------------------------------
for _m21d_e08_f in roles/node_exporter/tasks/main.yml roles/node_exporter/templates/node_exporter.service.j2 \
                   playbooks/node-exporter.yml playbooks/supervision-cibles.yml; do
  check_cmd "plateforme/ansible (main) : $_m21d_e08_f" _m21d_fichier_main plateforme/ansible "$_m21d_e08_f"
done
check_output "Rôle node_exporter : archive amont vérifiée par empreinte sha256" 'sha256' \
  _m21d_contenu_main plateforme/ansible roles/node_exporter/defaults/main.yml
check_cmd "plateforme/observabilite (main) : scrape/vms.yaml (généré depuis NetBox)" \
  _m21d_fichier_main plateforme/observabilite scrape/vms.yaml

# --- 2. La ScrapeConfig ---------------------------------------------------------------------------
_m21d_e08_sc="$(_m21d_k -n "$_M21D_NS" get scrapeconfigs.monitoring.coreos.com vms -o json)"
check_cmd "ScrapeConfig vms : job « vms », étiquetée $_M21D_SELECTEUR=oui" _m21d_json "$_m21d_e08_sc" \
  '.spec.jobName == "vms" and .metadata.labels[$l] == "oui"' --arg l "$_M21D_SELECTEUR"
check_cmd "ScrapeConfig vms : HTTPS, certificat vérifié par la racine MédiSphère (jamais insecureSkipVerify)" _m21d_json "$_m21d_e08_sc" \
  '(.spec.scheme | ascii_downcase) == "https" and ((.spec.tlsConfig.ca.configMap.name // .spec.tlsConfig.ca.secret.name // "") | length > 0)
   and ((.spec.tlsConfig.insecureSkipVerify // false) | not)'
check_cmd "ScrapeConfig vms : au moins $_M21D_VMS cibles sur le port 9100, désignées par leur nom" _m21d_json "$_m21d_e08_sc" \
  '[.spec.staticConfigs[].targets[]] | length >= ($n | tonumber) and all(test("^[a-z0-9-]+\\.par1\\.medisphere\\.internal:9100$"))' \
  --arg n "$_M21D_VMS"

# --- 3. Ce que voit Prometheus ----------------------------------------------------------------------
check_cmd "Au moins $_M21D_VMS VMs du socle collectées et up (count(up{job=\"vms\"} == 1))" \
  _m21d_au_moins 'count(up{job="vms"} == 1)' "$_M21D_VMS"
check_cmd "Aucune cible vms en échec" _m21d_vide 'up{job="vms"} == 0'
check_cmd "Étiquettes site, role et equipe sur toutes les cibles vms" _m21d_vide 'up{job="vms", site="" } or up{job="vms", role=""} or up{job="vms", equipe=""}'
check_cmd "node_exporter 1.12 partout (plus de paquet Debian 1.9)" _m21d_vide 'node_exporter_build_info{job="vms", version!~"1\\.12\\..*"}'
check_cmd "Métrique d'inventaire medisphere_info toujours publiée (collecteur textfile)" \
  _m21d_au_moins 'count(medisphere_info{job="vms"})' "$_M21D_VMS"

# --- 4. Le TLS, vu d'adm01 --------------------------------------------------------------------------
for _m21d_e08_h in "${_M21D_HOTES_TLS[@]}"; do
  check_http "$_m21d_e08_h : https://$_m21d_e08_h.$_M21D_DOMAINE:9100/metrics, certificat vérifié par la racine du système" \
    "https://$_m21d_e08_h.$_M21D_DOMAINE:9100/metrics" 200
  check_http "$_m21d_e08_h : le HTTP en clair est refusé (400)" "http://$_m21d_e08_h.$_M21D_DOMAINE:9100/metrics" 400
done
