# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M10-E40 « Panne : les calculs sont down » : nova-compute actifs et joignables,
# conteneurs sains, RabbitMQ joignable depuis chaque calcul, aucune règle locale ne le bloque.
# Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E40 — Les calculs sont joignables"
require_cmd openstack jq ssh

for _m10_e40_h in "${_m10x_cmps[@]}"; do
  check_output "$_m10_e40_h : nova-compute activé et joignable (enabled up)" '^enabled up$' \
    _m10x_etat_calcul "$_m10_e40_h"
  check_cmd "$_m10_e40_h : nova_compute en service (et non « unhealthy »)" _m10x_ctr_sain "$_m10_e40_h" nova_compute
  check_cmd "$_m10_e40_h : nova_libvirt en service" _m10x_ctr_sain "$_m10_e40_h" nova_libvirt
  check_ssh "$_m10_e40_h : RabbitMQ (osctl01, 5671 ou 5672) joignable en TCP" "$_m10_e40_h" \
    'timeout 3 bash -c "exec 3<>/dev/tcp/10.10.50.51/5672" 2>/dev/null || timeout 3 bash -c "exec 3<>/dev/tcp/10.10.50.51/5671" 2>/dev/null'
  check_ssh "$_m10_e40_h : aucune règle nftables locale ne rejette AMQP (5671/5672)" "$_m10_e40_h" \
    '! sudo -n nft list ruleset 2>/dev/null | grep -E "dport" | grep -E "567[12]" | grep -Eq "reject|drop"'
done
check_cmd "panne M10-E40 close (lab/bin/break 10 40 --annuler après réparation)" _m10x_aucune_panne_active E40
