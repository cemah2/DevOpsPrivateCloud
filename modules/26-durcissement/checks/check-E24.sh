# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E24.sh — M26-E24 « Conformité continue : analyses hebdomadaires, rapports, alertes »
# À lancer depuis adm01. Lecture seule : métriques et règles (Thanos Query), minuterie et droits des
# identifiants sur un échantillon de VMs (SSH, sudo -n stat), objets du compartiment conformite
# (identité de LECTURE), fichiers sur main de plateforme/observabilite et plateforme/medisphere.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E24 — Conformité continue : analyses hebdomadaires, rapports, alertes"
require_cmd jq curl ssh aws

title "Métriques de conformité (Thanos Query)"
_m26_e24_sup="$(_m26p_valeur 'count(up{job=~"vms|node-exporter"} == 1)')"
_m26_e24_ana="$(_m26p_valeur 'count(count by (instance) (medisphere_conformite_derniere_analyse_secondes))')"
check_cmd "des hôtes publient medisphere_conformite_* (${_m26_e24_ana:-0} sur ${_m26_e24_sup:-?} supervisés)" \
  _m26p_compare "${_m26_e24_ana:-0}" '>' 0
check_output "aucun hôte supervisé (VMs, nœuds) sans analyse" '^0$' \
  _m26p_nb '(up{job=~"vms|node-exporter"} == 1) unless on (instance) medisphere_conformite_derniere_analyse_secondes'
check_output "chaque hôte analysé l'est pour les deux référentiels (CIS et ANSSI)" '^0$' \
  _m26p_nb 'count by (instance) (medisphere_conformite_score) < 2'
check_output "les deux référentiels sont présents (cis_l1_serveur, anssi_intermediaire)" '^2$' \
  _m26p_nb 'count by (referentiel) (medisphere_conformite_score{referentiel=~"cis_l1_serveur|anssi_intermediaire"})'
_m26_e24_age="$(_m26p_valeur 'max(time() - medisphere_conformite_derniere_analyse_secondes)')"
check_cmd "aucune analyse de plus de 8 jours (la plus ancienne : ${_m26_e24_age:-?} s)" _m26p_compare "${_m26_e24_age}" '<' 691200
check_output "l'indice Lynis est publié par tous les hôtes analysés" '^0$' \
  _m26p_nb 'count by (instance) (medisphere_conformite_score) unless on (instance) medisphere_lynis_indice'

title "Minuterie sur un échantillon de VMs"
for _m26_e24_vm in "${_M26P_VMS[@]}"; do
  check_ssh "$_m26_e24_vm : conformite-analyse.timer activé et actif" "$_m26_e24_vm" \
    'systemctl is-enabled --quiet conformite-analyse.timer && systemctl is-active --quiet conformite-analyse.timer'
  check_ssh_output "$_m26_e24_vm : décalage aléatoire configuré" "$_m26_e24_vm" '^RandomizedDelayUSec=[1-9]' \
    'systemctl show conformite-analyse.timer -p RandomizedDelayUSec'
  check_ssh_output "$_m26_e24_vm : /etc/medisphere/conformite/s3.env en 600, propriétaire root" "$_m26_e24_vm" '^600 root$' \
    'sudo -n stat -c "%a %U" /etc/medisphere/conformite/s3.env'
done

title "Compartiment conformite (s3-01, identité de lecture)"
check_cmd "identité de lecture présente sur adm01 ($_M26P_S3_ENV, mode 600)" \
  bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_M26P_S3_ENV"
# Objets des 8 derniers jours (dossiers AAAA-MM-JJ/<hôte>/).
_m26_e24_objets=""
for _m26_e24_j in 0 1 2 3 4 5 6 7 8; do
  _m26_e24_d="$(date -u -d "-$_m26_e24_j day" +%F)"
  _m26_e24_objets+="$(_m26p_s3 s3api list-objects-v2 --bucket conformite --prefix "$_m26_e24_d/" 2>/dev/null \
    | jq -r '.Contents[]?.Key' 2>/dev/null || true)"$'\n'
done
# _m26_e24_depose HÔTE — un ARF et un rapport HTML (CIS et ANSSI) de l'hôte parmi les objets lus.
_m26_e24_depose() {
  local r
  for r in cis_l1_serveur-arf.xml cis_l1_serveur-rapport.html anssi_intermediaire-arf.xml anssi_intermediaire-rapport.html; do
    grep -Fq "/$1/$r.gz" <<<"$_m26_e24_objets" || return 1
  done
}
for _m26_e24_vm in "${_M26P_VMS[@]}"; do
  check_cmd "$_m26_e24_vm : ARF et rapports HTML (CIS, ANSSI) de moins de 8 jours dans le compartiment" \
    _m26_e24_depose "$_m26_e24_vm"
done
_m26_e24_vers="$(_m26p_s3 s3api get-bucket-versioning --bucket conformite 2>/dev/null || true)"
if [[ -n "$_m26_e24_vers" ]]; then
  check_output "le compartiment conformite est versionné" '"Enabled"' echo "$_m26_e24_vers"
else
  skip "versionnage du compartiment conformite" "non lisible avec l'identité de lecture (Read:conformite)"
fi

title "Alertes et documentation"
for _m26_e24_a in ConformiteDegradee ConformiteSousObjectif ConformiteAnalyseAbsente; do
  check_cmd "alerte $_m26_e24_a chargée par Prometheus" _m26p_alerte_chargee "$_m26_e24_a"
done
_m26_e24_tests() { _m26p_arbre "$_M26P_OBS" tests | grep -Eqi 'conformite'; }
check_cmd "$_M26P_OBS : tests/ contient les tests des règles de conformité" _m26_e24_tests
check_cmd "$_M26P_DOC : docs/securite/durcissement/conformite-continue.md sur main" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement 'conformite-continue\.md$' 20 'ARF' 'tailoring|profil adapt'
