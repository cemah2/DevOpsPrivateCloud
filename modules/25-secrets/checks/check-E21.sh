# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E21.sh — M25-E21 « Audit : qui a lu quel secret ».
# Vérifie, sur chaque nœud du coffre qui existe (vault01 obligatoire ; vault02-03 à partir d'E24) :
# dispositif d'audit déclaré dans openbao.hcl (fichier, accessors en clair), fichier 0640 openbao,
# rotation avec rechargement, Alloy qui lit le fichier ; puis la chaîne jusqu'au bout : lignes de
# {service="openbao"} dans le locataire audit, accessors en clair, règles du ruler chargées et
# saines (audit et plateforme), documentation des requêtes.
# Lecture seule (sudo -n en consultation sur les nœuds, GET sur Loki).

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E21 — Audit : qui a lu quel secret"
require_cmd jq curl

_m25c_e21_recent=0
for _m25c_e21_n in "${_M25C_COFFRES[@]}"; do
  if ! _m25c_noeud_joignable "$_m25c_e21_n"; then
    if [[ "$_m25c_e21_n" == vault01 ]]; then
      check_cmd "$_m25c_e21_n joignable en SSH (compte admin, sudo -n)" false
    else
      skip "audit sur $_m25c_e21_n" "nœud absent ou injoignable (créé en M25-E24)"
    fi
    continue
  fi
  check_cmd "$_m25c_e21_n : dispositif « file » déclaré dans openbao.hcl, vers /var/log/openbao/audit.log" \
    _m25c_sur "$_m25c_e21_n" 'grep -Eq "^audit \"file\" \"[^\"]+\"" /etc/openbao/openbao.hcl && grep -Eq "file_path *= *\"/var/log/openbao/audit.log\"" /etc/openbao/openbao.hcl'
  check_cmd "$_m25c_e21_n : accessors en clair dans l'audit (hmac_accessor = \"false\")" \
    _m25c_sur "$_m25c_e21_n" 'grep -Eq "hmac_accessor *= *\"false\"" /etc/openbao/openbao.hcl'
  check_cmd "$_m25c_e21_n : audit.log en 0640, propriétaire openbao" \
    _m25c_sur "$_m25c_e21_n" '[ "$(stat -c "%a %U" /var/log/openbao/audit.log)" = "640 openbao" ]'
  check_cmd "$_m25c_e21_n : rotation quotidienne avec rechargement d'OpenBao (/etc/logrotate.d/openbao-audit)" \
    _m25c_sur "$_m25c_e21_n" 'grep -q "/var/log/openbao/audit.log" /etc/logrotate.d/openbao-audit && grep -Eq "systemctl (reload|kill)" /etc/logrotate.d/openbao-audit && ! grep -q copytruncate /etc/logrotate.d/openbao-audit'
  check_cmd "$_m25c_e21_n : Alloy lit le journal d'audit (groupe openbao, locataire audit)" \
    _m25c_sur "$_m25c_e21_n" 'id -nG alloy | grep -qw openbao && grep -q "/var/log/openbao/audit.log" /etc/alloy/config.alloy && grep -Eq "tenant_id *= *\"audit\"" /etc/alloy/config.alloy && systemctl is-active --quiet alloy'
  # Le nœud ACTIF écrit l'audit : l'authentification AppRole de ce check y laisse des lignes.
  if _m25c_sur "$_m25c_e21_n" 'find /var/log/openbao/audit.log -mmin -15 | grep -q .'; then
    _m25c_e21_recent=1
  fi
done
check_cmd "un nœud au moins (l'actif) a écrit son journal d'audit dans les 15 dernières minutes" test "$_m25c_e21_recent" -eq 1

# La chaîne jusqu'à Loki.
_m25c_e21_nb="$(_m25c_loki_nb '{service="openbao"}' audit 1h)"
check_cmd "Loki, locataire audit : lignes {service=\"openbao\"} dans la dernière heure ($_m25c_e21_nb)" test "${_m25c_e21_nb:-0}" -gt 0
_m25c_e21_hmac="$(_m25c_loki_nb '{service="openbao"} |= `"accessor":"hmac-sha256:`' audit 15m)"
_m25c_e21_clair="$(_m25c_loki_nb '{service="openbao"} |~ `"accessor":"[A-Za-z0-9]{24}"`' audit 15m)"
_m25c_e21_accessors() { [[ "${_m25c_e21_clair:-0}" -gt 0 && "${_m25c_e21_hmac:-1}" -eq 0 ]]; }
check_cmd "Loki : accessors en clair dans l'audit récent (aucun en HMAC sur 15 min)" _m25c_e21_accessors
# Loki doit répondre (lignes dans audit) pour que « rien dans plateforme » ait un sens.
_m25c_e21_plateforme="$(_m25c_loki_nb '{service="openbao"}' plateforme 1h)"
_m25c_e21_locataire() { [[ "${_m25c_e21_nb:-0}" -gt 0 && "${_m25c_e21_plateforme:-1}" -eq 0 ]]; }
check_cmd "Loki : aucun journal d'audit d'OpenBao dans le locataire plateforme (mauvais locataire)" _m25c_e21_locataire

_m25c_e21_regles="$(_m25c_regles_loki audit)"
for _m25c_e21_r in OpenBaoJetonRacineUtilise OpenBaoPolitiqueModifiee OpenBaoCleTransitModifiee; do
  check_cmd "ruler de Loki (audit) : règle $_m25c_e21_r chargée et saine" \
    _m25c_json "$_m25c_e21_regles" '[.data.groups[]?.rules[]? | select(.name == $n and .health != "err")] | length == 1' --arg n "$_m25c_e21_r"
done
check_cmd "ruler de Loki (plateforme) : règle OpenBaoAuditImpossible chargée et saine" \
  _m25c_json "$(_m25c_regles_loki plateforme)" '[.data.groups[]?.rules[]? | select(.name == "OpenBaoAuditImpossible" and .health != "err")] | length == 1'
check_cmd "documentation : $_M25C_DOC_SECRETS/audit-openbao.md (requêtes LogQL, sys/audit-hash)" \
  _m25c_contient "$_M25C_P_DOC" "$_M25C_DOC_SECRETS/audit-openbao.md" 'audit-hash'
