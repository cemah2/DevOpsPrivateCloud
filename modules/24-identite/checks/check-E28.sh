# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E28.sh — M24-E28 : Bris de glace : comptes de secours et procédure éprouvée
# À lancer depuis adm01. Lecture seule : RB-240 sur main, règles du ruler de Loki (locataire audit),
# trace d'une connexion de kc-secours dans Loki (31 jours), compte kc-secours par SELECT sur idp01.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E28 — Bris de glace : comptes de secours et procédure éprouvée"
require_cmd jq curl

_m24p_e28_rb="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -Ei 'RB-240' | head -n 1 || true)"
_m24p_e28_c=""
[[ -n "$_m24p_e28_rb" ]] && _m24p_e28_c="$(_m24p_doc "$_m24p_e28_rb")"
check_cmd "RB-240 (bris de glace) sur main de plateforme/medisphere" test -n "$_m24p_e28_c"
check_output "RB-240 : un tableau des comptes de secours d'au moins dix services" '^([1-9][0-9]+)$' \
  _m24p_nb_lignes "$_m24p_e28_c" '^\| *(Keycloak|FreeIPA|GitLab|Argo CD|Grafana|Harbor|Proxmox|PBS|NetBox|Cluster|VMs|OpenBao)'
check_cmd "RB-240 : critères de déclenchement et procès-verbal d'essai daté" _m24p_tous "$_m24p_e28_c" \
  'quand|crit[èe]re' 'proc[èe]s-verbal' '20[0-9]{2}-[01][0-9]-[0-3][0-9]'

_m24p_e28_regles="$(_m24p_ruler audit)"
check_cmd "Ruler de Loki (audit) : alerte d'usage de kc-secours chargée" _m24d_contient "$_m24p_e28_regles" '^BrisDeGlaceKeycloak$'
check_output "Ruler de Loki (audit) : au moins trois alertes de bris de glace" '^([3-9]|[1-9][0-9]+)$' \
  _m24p_nb_lignes "$_m24p_e28_regles" '^BrisDeGlace'
check_cmd "Loki (audit) : une connexion de kc-secours au royaume master dans les 31 derniers jours (essai)" \
  _m24p_compare "$(_m24p_loki_lignes '{service="keycloak"} |= "kc-secours" |= "realmName"' audit 744h)" '>' 0
check_output "master : kc-secours actif" '^true$' \
  _m24p_sql "SELECT u.enabled FROM user_entity u JOIN realm r ON r.id = u.realm_id WHERE r.name = 'master' AND u.username = 'kc-secours'"
check_output "master : kc-secours sans OTP (second facteur lié à un téléphone : inutilisable le jour J)" '^0$' \
  _m24p_sql "SELECT count(*) FROM credential c JOIN user_entity u ON u.id = c.user_id JOIN realm r ON r.id = u.realm_id WHERE r.name = 'master' AND u.username = 'kc-secours' AND c.type = 'otp'"
