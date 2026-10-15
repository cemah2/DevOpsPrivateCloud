# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M14-E40 « Panne : un membre etcd est en détresse » : trois membres démarrés et en
# bonne santé, aucune alarme, aucune clé hors de /registry/, quota d'espace par défaut ou plus grand,
# horloges synchronisées, RB-146, panne close. Lecture seule (etcdctl endpoint/member/alarm list,
# get --keys-only).

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E40 — etcd : trois membres en bonne santé"
require_cmd ssh

if _m14x_etcd 'true'; then
  check_output "trois membres démarrés (member list)" '^3$' \
    _m14x_etcd 'e_ member list 2>/dev/null | grep -c ", started, "'
  check_output "les trois membres répondent (endpoint health)" '^3$' \
    _m14x_etcd 'e_ --endpoints="$EP" endpoint health 2>&1 | grep -c "is healthy"'
  check_output "aucune alarme etcd (alarm list vide)" '^vide$' \
    _m14x_etcd 'a="$(e_ alarm list 2>/dev/null)"; [ -z "$a" ] && echo vide'
  check_output "aucune clé hors de /registry/" '^0$' \
    _m14x_etcd 'e_ get "" --from-key --keys-only 2>/dev/null | grep -v "^$" | grep -vc "^/registry/"'
else
  skip "état d'etcd" "aucun nœud de contrôle ne répond avec etcdctl"
fi
# shellcheck disable=SC2016  # commandes évaluées sur le nœud
for _m14_e40_h in "${_m14x_cp[@]}"; do
  check_cmd "$_m14_e40_h : quota d'espace etcd par défaut ou d'au moins 2 Gio" \
    _m14x_noeud "$_m14_e40_h" 'q="$(sed -n "s/.*--quota-backend-bytes=\([0-9]*\).*/\1/p" /etc/kubernetes/manifests/etcd.yaml)"; [ -z "$q" ] || [ "$q" -ge 2147483648 ]'
  check_cmd "$_m14_e40_h : horloge synchronisée (NTPSynchronized=yes)" \
    _m14x_noeud "$_m14_e40_h" '[ "$(timedatectl show -p NTPSynchronized --value)" = yes ]'
  _m14_e40_ecart() {
    local t
    t="$(remote "$1" 'date +%s' </dev/null 2>/dev/null)" || return 1
    [[ "$t" =~ ^[0-9]+$ ]] && (($(date +%s) - t < 5 && t - $(date +%s) < 5))
  }
  check_cmd "$_m14_e40_h : écart d'horloge avec adm01 inférieur à 5 s" _m14_e40_ecart "$_m14_e40_h"
done
check_cmd "RB-146 (etcd en détresse) publié et commité" _m14x_doc_commite 'docs/kubernetes/runbooks/RB-146-*.md'
check_cmd "panne M14-E40 close (lab/bin/break 14 40 --annuler après réparation)" _m14x_aucune_panne_active E40
