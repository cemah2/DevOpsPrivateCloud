# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts de « bash -c » entre apostrophes (arguments en $1)
# check-E13.sh — M13-E13 « Répliquer vers un second registre »
# Lecture seule : API Harbor de reg01 et de reg02 (robots wb-checks), certificat de reg02, configuration
# de la VM sur pve01 (qm config), documentation et matrice des flux (API GitLab).

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E13 — Répliquer vers un second registre"
require_cmd jq curl openssl

title "reg02"
check_cmd "la VM 2131 existe sur pve01" remote "$WB_PVE_HOST" "qm status 2131"
check_ssh_output "la VM 2131 s'appelle reg02 et porte l'étiquette env-m13" "$WB_PVE_HOST" \
  '^name: reg02$' "qm config 2131 | grep -qE '^tags:.*env-m13' && qm config 2131 | grep -E '^name:'"
check_dns "reg02.par1.medisphere.internal → 10.10.99.31" reg02.par1.medisphere.internal A '^10\.10\.99\.31$'
check_cmd "Harbor de reg02 répond « healthy » en HTTPS" _m13p_sante "$_M13P_REG02_URL"
check_cmd "certificat de reg02 émis par la PKI MédiSphère, à son nom, valable plus de 3 jours" \
  _m13p_cert "$_M13P_REG02_NOM" 443 3
check_cmd "robot des checks de reg02 lisible ($_M13P_REG02_FICHIER, mode 600)" \
  bash -c "[[ -r '$_M13P_REG02_FICHIER' && \$(stat -c %a '$_M13P_REG02_FICHIER') == 600 ]]"

title "reg01 : endpoint et politique"
_m13_e13_reg="$(_m13p_api "registries?page_size=50")" || _m13_e13_reg=""
check_cmd "un endpoint de type harbor vers reg02" _m13p_jq "$_m13_e13_reg" \
  "any(.[]; .type == \"harbor\" and (.url | test(\"reg02\\\\.par1\")))"
check_cmd "l'endpoint vérifie le certificat (insecure = false)" _m13p_jq "$_m13_e13_reg" \
  "any(.[]; (.url | test(\"reg02\\\\.par1\")) and .insecure == false)"
check_cmd "l'endpoint est « healthy »" _m13p_jq "$_m13_e13_reg" \
  "any(.[]; (.url | test(\"reg02\\\\.par1\")) and .status == \"healthy\")"
_m13_e13_pol="$(_m13p_api "replication/policies?name=medisphere-vers-reg02")" || _m13_e13_pol=""
_m13_e13_p='(.[]? | select(.name == "medisphere-vers-reg02"))'
check_cmd "politique medisphere-vers-reg02 présente et active" _m13p_jq "$_m13_e13_pol" "any($_m13_e13_p; .enabled == true)"
check_cmd "… en poussée vers reg02 (destination = endpoint reg02)" _m13p_jq "$_m13_e13_pol" \
  "any($_m13_e13_p; (.dest_registry.url // \"\") | test(\"reg02\\\\.par1\"))"
check_cmd "… planifiée (déclencheur « scheduled » avec cron)" _m13p_jq "$_m13_e13_pol" \
  "any($_m13_e13_p; .trigger.type == \"scheduled\" and ((.trigger.trigger_settings.cron // \"\") | length > 0))"
check_cmd "… filtrée sur medisphere/** et les étiquettes v*" _m13p_jq "$_m13_e13_pol" \
  "any($_m13_e13_p; any(.filters[]?; .type == \"name\" and .value == \"medisphere/**\") and any(.filters[]?; .type == \"tag\" and (.value | startswith(\"v\"))))"
check_cmd "… sans propagation des suppressions" _m13p_jq "$_m13_e13_pol" "any($_m13_e13_p; .deletion == false)"
_m13_e13_id="$(jq -r "[$_m13_e13_p | .id][0] // empty" <<<"${_m13_e13_pol:-[]}" 2>/dev/null)" || _m13_e13_id=""
_m13_e13_exe=""
[[ -z "$_m13_e13_id" ]] || _m13_e13_exe="$(_m13p_api "replication/executions?policy_id=$_m13_e13_id&page_size=1&sort=-start_time")" || _m13_e13_exe=""
check_cmd "dernière exécution de la politique réussie" _m13p_jq "$_m13_e13_exe" '.[0].status == "Succeed"'

title "La copie sur reg02"
_m13_e13_d1="$(_m13p_digest_version medisphere mediagenda-api)" || _m13_e13_d1=""
_m13_e13_a2="$(_m13p_derniere_version medisphere mediagenda-api _m13p_api2)" || _m13_e13_a2=""
check_cmd "medisphere/mediagenda-api : la dernière version v* de reg01 existe sur reg02 avec le même digest" \
  _m13p_api2 "projects/medisphere/repositories/mediagenda-api/artifacts/${_m13_e13_d1:-absent}"
check_cmd "… et sa signature Cosign a été répliquée" \
  bash -c 'jq -e "any(.accessories[]?; .type == \"signature.cosign\")" >/dev/null 2>&1 <<<"$1"' _ \
  "$(_m13p_api2 "projects/medisphere/repositories/mediagenda-api/artifacts/${_m13_e13_d1:-absent}?with_accessory=true" || true)"
check_cmd "la dernière version v* de reg02 est signée" _m13p_signee "$_m13_e13_a2"

title "Code et documentation"
check_cmd "matrice des flux : reg02 (10.10.99.31) présent dans group_vars/role_routeur/pare_feu.yml" \
  _m13p_fichier_motifs plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml '10\.10\.99\.31'
check_cmd "docs/socle/matrice-flux.md cite reg02" _m13p_doc_main docs/socle/matrice-flux.md 'reg02'
check_cmd "docs/registre/replication.md sur main (sens, filtres, RPO)" \
  _m13p_doc_main docs/registre/replication.md 'RPO' 'v\*' 'medisphere'
