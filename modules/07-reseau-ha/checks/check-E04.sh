# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées par bash -c ou sur l'hôte distant
#
# check-E04.sh — M07-E04 : Bonding Linux : active-backup et LACP
# À lancer depuis adm01. Lecture seule : état de net01 en SSH (/proc/net/bonding dans les espaces
# de noms, sudo -n), API GitLab en lecture.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E04 — Bonding Linux : active-backup et LACP"
require_cmd jq curl

check_cmd "net01 : m07-bond.service actif et lancé au démarrage" _m07d_actif net01 m07-bond.service

for _m07d_e04_ns in ns-srv ns-sw; do
  _m07d_e04_b="$(remote net01 "sudo -n ip netns exec $_m07d_e04_ns cat /proc/net/bonding/bond0" 2>/dev/null || true)"
  check_output "$_m07d_e04_ns : bond0 en 802.3ad (LACP)" 'Bonding Mode: IEEE 802\.3ad' printf '%s' "$_m07d_e04_b"
  check_output "$_m07d_e04_ns : surveillance de la porteuse toutes les 100 ms" 'MII Polling Interval \(ms\): 100$' \
    printf '%s' "$_m07d_e04_b"
  check_output "$_m07d_e04_ns : répartition par flux (hachage layer3+4)" 'Transmit Hash Policy: layer3\+4' \
    printf '%s' "$_m07d_e04_b"
  # Les deux esclaves sont dans l'agrégateur ACTIF (pas deux agrégats d'un lien chacun).
  check_output "$_m07d_e04_ns : les deux liens sont dans l'agrégateur actif" 'Number of ports: 2' \
    printf '%s' "$_m07d_e04_b"
  # Un partenaire non nul = des LACPDU reçues de l'autre côté.
  check_cmd "$_m07d_e04_ns : un partenaire LACP est identifié (LACPDU reçues)" \
    bash -c 'grep -E "Partner Mac Address:" <<<"$1" | grep -qv "00:00:00:00:00:00"' _ "$_m07d_e04_b"
  check_cmd "$_m07d_e04_ns : deux esclaves, porteuse présente sur les deux" \
    bash -c '[[ "$(grep -c "^Slave Interface:" <<<"$1")" == 2 ]] && [[ "$(grep -c "^MII Status: up" <<<"$1")" == 3 ]]' _ "$_m07d_e04_b"
done

check_cmd "ns-srv (172.31.70.1) joint ns-sw (172.31.70.2) à travers l'agrégat" _m07d_ping net01 172.31.70.2 ns-srv

check_cmd "plateforme/ansible (main) : rôle bonding" _m07d_ansible_main roles/bonding/tasks/main.yml
check_cmd "plateforme/ansible (main) : playbook m07-net01.yml" _m07d_ansible_main playbooks/m07-net01.yml
