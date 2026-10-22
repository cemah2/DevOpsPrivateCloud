# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E25.sh — M25-E25 « Auto-descellement : kms01 et migration du seal » : kms01 sain (Shamir,
# descellé) ; les trois nœuds en seal transit avec clés de récupération ; jeton hors de openbao.hcl,
# dans /etc/openbao/kms.env (root, 600) lu par l'unité ; plus de bloc shamir ; journal du redémarrage
# simultané ; RB-251 sur main.
# À lancer depuis adm01. Lecture seule : sys/health et sys/seal-status sans jeton, SSH en consultation
# (stat, grep, systemctl show), GitLab.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E25 — Auto-descellement : kms01 et migration du seal"
require_cmd curl jq

check_cmd "$_M25P_KMS : répond 200 (actif, descellé)" test "$(_m25p_code "$_M25P_KMS")" = 200
check_cmd "$_M25P_KMS : scellé par Shamir (pas d'auto-descellement), descellé" \
  _m25p_jq "$(_m25p_scellement "$_M25P_KMS")" '.type == "shamir" and .sealed == false and .recovery_seal == false'

for _m25_e25_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25_e25_n : seal transit, descellé, clés de récupération (recovery_seal)" \
    _m25p_jq "$(_m25p_scellement "$_m25_e25_n")" '.type == "transit" and .sealed == false and .recovery_seal == true and .migration == false'
  check_ssh "$_m25_e25_n : /etc/openbao/kms.env existe, root, mode 600, non vide" "$_m25_e25_n" \
    'sudo -n test -s /etc/openbao/kms.env && [ "$(sudo -n stat -c %U:%a /etc/openbao/kms.env)" = root:600 ] && sudo -n grep -q "^BAO_TOKEN=" /etc/openbao/kms.env'
  check_ssh "$_m25_e25_n : openbao.hcl a un bloc seal transit actif, sans jeton ni bloc shamir" "$_m25_e25_n" \
    'f=/etc/openbao/openbao.hcl; sudo -n grep -Eq "^[[:space:]]*seal[[:space:]]+\"transit\"" $f \
     && ! sudo -n grep -Eq "^[[:space:]]*token[[:space:]]*=" $f \
     && ! sudo -n grep -Eq "^[[:space:]]*seal[[:space:]]+\"shamir\"" $f \
     && ! sudo -n grep -Eq "^[[:space:]]*disabled[[:space:]]*=[[:space:]]*\"?true" $f'
  check_ssh "$_m25_e25_n : l'unité openbao lit /etc/openbao/kms.env" "$_m25_e25_n" \
    'systemctl show openbao.service -p EnvironmentFiles --value | grep -q /etc/openbao/kms.env'
done

# Le redémarrage simultané (étape 5a) : le journal de travail note l'épreuve et le retour sans personne.
_m25_e25_journal() {
  local d="$HOME/m25/e25"
  [[ -d "$d" ]] || return 1
  grep -Eqil 'reboot|red[ée]marr' "$d"/* 2>/dev/null && grep -Eql '([01]?[0-9]|2[0-3])[:h][0-5][0-9]' "$d"/* 2>/dev/null
}
check_cmd "journal de travail (~/m25/e25/) : redémarrage simultané des trois nœuds, heures notées" _m25_e25_journal

_m25_e25_rb="$(_m25p_doc_chemin "$_M25P_DOC" "$_M25P_RB" 'RB-251[^/]*\.md$')"
check_cmd "RB-251 sur main de $_M25P_DOC (${_m25_e25_rb:-absent})" test -n "$_m25_e25_rb"
check_cmd "RB-251 : kms01 injoignable (reset-failed), kms01 scellé (dépositaires), perte de kms01, retour à Shamir" \
  _m25p_doc "$_M25P_DOC" "$_M25P_RB" 'RB-251[^/]*\.md$' 30 'reset-failed' 'd[ée]positaire' 'perte|perdu' 'shamir' 'migrat'
