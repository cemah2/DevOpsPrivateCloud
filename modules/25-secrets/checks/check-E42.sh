# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E42.sh — M25-E42 « Panne : l'auto-descellement échoue » : trois nœuds descellés (seal transit),
# un seul actif ; autopilot sain avec une tolérance d'au moins un ; kms01 descellé ; sur chaque nœud,
# kms.env identique (empreinte comparée ici, jamais affichée) et en 600, aucune règle locale ne filtre la
# sortie vers kms01:8200, unité non en échec, essai quotidien de l'auto-descellement actif ; métrique
# de l'essai collectée et alerte chargée ; journal INC-5242.
# Lecture seule : sys/health et sys/seal-status sans jeton, bao_api (autopilot), SSH en consultation
# (sudo -n : stat, sha256sum, nft list, systemctl), Prometheus, gitlab_api.

# shellcheck source=_m25-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert-b.sh"

title "M25-E42 — Panne : l'auto-descellement échoue"
require_cmd curl jq ssh
_m25p_connexion

for _m25y_e42_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25y_e42_n : descellé par le seal transit" \
    _m25p_jq "$(_m25p_scellement "$_m25y_e42_n")" '.type == "transit" and .sealed == false'
done
check_output "un seul nœud actif (200)" '^1$' bash -c 'grep -c . <<<"$1"' _ "$(_m25p_actifs)"
check_cmd "autopilot sain, tolérance aux pannes ≥ 1" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/state)" '.data.healthy == true and .data.failure_tolerance >= 1'
check_cmd "$_M25P_KMS : descellé (seal Shamir)" \
  _m25p_jq "$(_m25p_scellement "$_M25P_KMS")" '.sealed == false and .type == "shamir"'

_m25y_e42_empreintes=""
for _m25y_e42_n in "${_M25P_NOEUDS[@]}"; do
  check_ssh_output "$_m25y_e42_n : /etc/openbao/kms.env en 600, propriété root" "$_m25y_e42_n" '^600 root$' \
    'sudo -n stat -c "%a %U" /etc/openbao/kms.env'
  _m25y_e42_empreintes+="$(_m25p_ssh_sortie "$_m25y_e42_n" 'sha256sum /etc/openbao/kms.env | cut -d" " -f1')"$'\n'
  check_cmd "$_m25y_e42_n : aucune règle locale ne filtre la sortie vers $_M25Y_KMS_IP:8200" \
    bash -c '! grep -Eq "daddr $2 .*dport 8200 .*(reject|drop)" <<<"$1"' _ \
    "$(_m25p_ssh_sortie "$_m25y_e42_n" 'nft list ruleset')" "${_M25Y_KMS_IP//./\\.}"
  check_cmd "$_m25y_e42_n : unité openbao active, pas en échec" \
    _m25p_ssh "$_m25y_e42_n" 'systemctl is-active --quiet openbao && ! systemctl is-failed --quiet openbao'
  check_cmd "$_m25y_e42_n : essai quotidien de l'auto-descellement actif (openbao-essai-kms.timer)" \
    _m25p_ssh "$_m25y_e42_n" 'systemctl is-active --quiet openbao-essai-kms.timer'
done
check_output "kms.env identique sur les ${#_M25P_NOEUDS[@]} nœuds (empreintes comparées, non affichées)" '^1$' \
  bash -c 'grep -E "^[0-9a-f]{64}$" <<<"$1" | sort -u | grep -c .' _ "$_m25y_e42_empreintes"

check_output "métrique de l'essai collectée pour les ${#_M25P_NOEUDS[@]} nœuds, toutes à 1" "^${#_M25P_NOEUDS[@]}$" \
  _m25p_valeur 'count(medisphere_openbao_kms_essai_ok == 1)'
check_cmd "alerte chargée sur l'essai de l'auto-descellement (medisphere_openbao_kms_essai_*)" \
  _m25y_regle_presente 'medisphere_openbao_kms_essai_'
check_cmd "journal de diagnostic INC-5242 sur main (plateforme/medisphere)" _m25y_journal INC-5242
