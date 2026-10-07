# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E41.sh — M04-E41 « Panne : le playbook est devenu très lent » : parallélisme, multiplexage
# SSH et pipelining effectifs (configuration ET variables d'inventaire), élévation de privilèges
# rapide sur chaque hôte, et une mesure de bout en bout. Lecture seule (la mesure lance la
# commande « true » avec sudo sur le socle).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E41 — Performances d'Ansible"
require_cmd jq ssh

_m04_e41_base="$(_m04x_ansible ansible-config dump 2>/dev/null)" || _m04_e41_base=""
_m04_e41_ssh="$(_m04x_ansible ansible-config dump -t connection ssh 2>/dev/null)" || _m04_e41_ssh=""
_m04_e41_vars="$(_m04x_ansible ansible-inventory --list 2>/dev/null)" || _m04_e41_vars='{}'

_m04_e41_forks() {
  local n
  n="$(sed -nE 's/^DEFAULT_FORKS\(.*\) = ([0-9]+)$/\1/p' <<<"$_m04_e41_base")"
  [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 5))
}
_m04_e41_multiplexage() {
  local a
  a="$(sed -nE 's/^ssh_args\(.*\) = (.*)$/\1/p' <<<"$_m04_e41_ssh")"
  [[ "$a" == *ControlPersist* && "$a" != *ControlMaster=no* ]]
}
_m04_e41_pipelining() { grep -Eq '^pipelining\(.*\) = True$' <<<"$_m04_e41_ssh"; }
_m04_e41_vars_saines() {
  jq -e '[._meta.hostvars // {} | to_entries[] | .value
          | select((.ansible_pipelining == false) or (.ansible_ssh_pipelining == false)
                   or ((.ansible_ssh_args // "") | test("ControlMaster=no")))] | length == 0' \
    >/dev/null <<<"$_m04_e41_vars"
}
# Mesure de bout en bout : une commande avec élévation sur tout le socle.
_m04_e41_mesure() {
  local d f
  local o
  d="$(date +%s)"
  o="$(_m04x_ansible ansible socle -b -m ansible.builtin.command -a true -o 2>/dev/null)" || return 1
  f="$(date +%s)"
  # Les cinq hôtes ont répondu (un groupe vide répondrait vite… et à tort).
  (($(grep -Ec ' \| (CHANGED|SUCCESS) ' <<<"$o") >= 5)) && ((f - d <= 20))
}

check_cmd "forks effectif ≥ 5" _m04_e41_forks
check_cmd "connexion ssh : multiplexage actif (ControlPersist, pas de ControlMaster=no)" _m04_e41_multiplexage
check_cmd "connexion ssh : pipelining activé" _m04_e41_pipelining
check_cmd "inventaire : aucune variable de connexion qui désactive multiplexage ou pipelining" _m04_e41_vars_saines
for _m04_e41_h in gw01 dns01 git01 runner01; do
  check_ssh "$_m04_e41_h : sudo répond en moins de 2 s" "$_m04_e41_h" \
    's=$(date +%s%N); sudo -n true; e=$(date +%s%N); [ $(( (e - s) / 1000000 )) -lt 2000 ]'
done
check_ssh "git01 : aucune commande externe lancée à chaque sudo (pam_exec)" git01 '! grep -Eq "^[^#]*pam_exec" /etc/pam.d/sudo'
check_cmd "« ansible socle -b -m command -a true » en moins de 20 s" _m04_e41_mesure
check_cmd "panne M04-E41 close" _m04x_aucune_panne_active E41
