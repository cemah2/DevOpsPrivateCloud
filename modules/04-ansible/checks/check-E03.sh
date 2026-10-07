# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E03.sh — M04-E03 : Inventaire statique du socle
# À lancer depuis adm01. Lecture seule : ansible-inventory (lecture de l'inventaire),
# module ping (connexion et Python des hôtes, aucune modification), API GitLab.

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E03 — Inventaire statique du socle"
require_cmd git jq curl

check_cmd "inventories/lab/hosts.yml présent dans la copie de travail" test -s "$_M04_SRC/inventories/lab/hosts.yml"
check_cmd "inventories/lab/hosts.yml publié sur main" _m04_fichier_main inventories/lab/hosts.yml

_m04_inv="$(_m04_ans ansible-inventory --list 2>/dev/null)" || _m04_inv=""
check_cmd "ansible-inventory lit l'inventaire du projet sans erreur" jq -e '._meta.hostvars' <<<"$_m04_inv"

# _m04_groupe GROUPE — hôtes du groupe (directs ou par sous-groupes), triés, séparés par des espaces
_m04_groupe() {
  jq -r --arg g "$1" '
    def hotes($n): ((.[$n].hosts // []) + ([(.[$n].children // [])[] as $c | hotes($c)] | add // []));
    [hotes($g)] | flatten | unique | join(" ")' <<<"$_m04_inv" 2>/dev/null || true
}
check_output "groupe socle : les cinq hôtes du socle" '^adm01 dns01 git01 gw01 runner01$' _m04_groupe socle
check_output "groupe role_routeur : gw01" '^gw01$' _m04_groupe role_routeur
check_output "groupe role_bastion : adm01" '^adm01$' _m04_groupe role_bastion
check_output "groupe role_dns : dns01" '^dns01$' _m04_groupe role_dns
check_output "groupe role_gitlab : git01" '^git01$' _m04_groupe role_gitlab
check_output "groupe role_runner : runner01" '^runner01$' _m04_groupe role_runner
# Les six groupes attendus, tous enfants directs de all (un groupe de plus — role_semaphore
# après M04-E28 — ne gêne pas ; ce qui est contrôlé : aucun role_* imbriqué sous socle).
check_output "groupes socle et role_* au même niveau (enfants directs de all, comme en dynamique)" '^6$' \
  jq -r '[.all.children[] | select(IN("socle", "role_routeur", "role_bastion", "role_dns", "role_gitlab", "role_runner"))] | length' <<<"$_m04_inv"

# _m04_hv HÔTE VARIABLE — valeur brute d'une variable d'hôte dans l'inventaire
_m04_hv() { jq -r --arg h "$1" --arg v "$2" '._meta.hostvars[$h][$v] // empty' <<<"$_m04_inv" 2>/dev/null || true; }
for _m04_paire in gw01:10.10.10.1 adm01:10.10.10.10 dns01:10.10.20.10 git01:10.10.20.12 runner01:10.10.20.15; do
  _m04_h="${_m04_paire%%:*}"
  check_output "$_m04_h : ansible_host = ${_m04_paire#*:} (adresse IP, indépendante du DNS)" \
    "^${_m04_paire#*:}\$" _m04_hv "$_m04_h" ansible_host
done
check_output "connexion des hôtes avec le compte admin" '^admin$' _m04_hv dns01 ansible_user
check_output "adm01 géré en connexion locale" '^local$' _m04_hv adm01 ansible_connection

# --- Vérification des clés d'hôte : jamais désactivée -----------------------------------------
check_cmd "aucun réglage du projet ne désactive la vérification des clés d'hôte" \
  bash -c '! git -C "$1" grep -nIiE "host_key_checking[[:space:]]*[=:][[:space:]]*(false|no|0)|StrictHostKeyChecking[[:space:]=]+no|UserKnownHostsFile[[:space:]=]+/dev/null" -- . >/dev/null 2>&1' \
  _ "$_M04_SRC"
check_cmd "le .ansible.cfg de ton compte ne désactive pas la vérification des clés d'hôte" \
  bash -c '! grep -sEiq "host_key_checking[[:space:]]*=[[:space:]]*(false|no|0)" "$HOME/.ansible.cfg"'

# --- Connexion effective -------------------------------------------------------------------
_m04_ping="$(_m04_json ansible socle -m ansible.builtin.ping)"
for _m04_h in $_M04_SOCLE; do
  check_output "$_m04_h répond au module ping (SSH, Python, compte)" '^pong$' \
    _m04_resultat "$_m04_ping" "$_m04_h" '.ping // empty'
done
