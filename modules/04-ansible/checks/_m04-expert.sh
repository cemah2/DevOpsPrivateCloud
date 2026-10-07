# shellcheck shell=bash
# _m04-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du
# module 04 (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule :
# Ansible n'est lancé qu'en lecture (ansible-inventory, ansible-config, ping, --check).
# Préfixe _m04x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m04x_src="${WB_SRC:-$HOME/src}/ansible"
_m04x_env="$HOME/.config/workbook/pve-ansible.env"
_m04x_vault="inventories/lab/group_vars/all/vault.yml"
# shellcheck disable=SC2034  # utilisé par les checks qui sourcent ce fichier
declare -A _m04x_ip=([gw01]=10.10.10.1 [adm01]=10.10.10.10 [dns01]=10.10.20.10 [git01]=10.10.20.12 [runner01]=10.10.20.15)

# _m04x_ansible COMMANDE [args…] — comme l'apprenant : racine du projet, environnement du projet.
_m04x_ansible() {
  local cmd="$1"
  shift
  (
    cd "$_m04x_src" || exit 1
    if [[ -r "$_m04x_env" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$_m04x_env"
      set +a
    fi
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    if [[ -x ".venv/bin/$cmd" ]]; then
      exec ".venv/bin/$cmd" "$@" </dev/null
    fi
    exec uv run --frozen --quiet "$cmd" "$@" </dev/null
  )
}

_m04x_inv_host() { _m04x_ansible ansible-inventory --host "$1" 2>/dev/null; }
# _m04x_ping HÔTE — l'hôte existe dans l'inventaire ET répond (un motif sans hôte renvoie 0).
_m04x_ping() {
  local o
  o="$(_m04x_ansible ansible "$1" -m ansible.builtin.ping -o 2>/dev/null)" || return 1
  grep -Eq "^$1 \| SUCCESS" <<<"$o"
}
_m04x_ssh_neuf() { ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1; }

# _m04x_hotes_groupe JSON GROUPE — hôtes d'un groupe (récursivement) d'une sortie --list.
_m04x_hotes_groupe() {
  jq -r --arg g "$2" '. as $inv
    | def h($g): ($inv[$g].hosts // []) + (($inv[$g].children // []) | map(h(.)) | add // []);
    h($g) | unique | .[]' <<<"$1" 2>/dev/null
}

# _m04x_var_fuseau — variable de fuseau du rôle base (valeur Europe/Paris), cf. M04-E37.
_m04x_var_fuseau() {
  local f v
  for f in "$_m04x_src/roles/base/defaults/main.yml" "$_m04x_src"/inventories/lab/group_vars/all/*.yml; do
    [[ -f "$f" ]] || continue
    v="$(sed -nE "s/^([a-z_][a-z0-9_]*):[[:space:]]*[\"']?Europe\/Paris[\"']?[[:space:]]*(#.*)?\$/\1/p" "$f" | head -n 1)"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  done
  return 1
}

# _m04x_sonde VARIABLE HÔTE — valeur effective de VARIABLE pour HÔTE dans un jeu qui applique le
# rôle base, avec les règles de précédence d'un vrai passage. Seule une tâche debug s'exécute
# (--check, --tags) ; le playbook temporaire (playbooks/.wb-sonde-check.yml) est retiré aussitôt.
_m04x_sonde() {
  local var="$1" hote="$2" pb="$_m04x_src/playbooks/.wb-sonde-check.yml" sortie
  [[ -d "$_m04x_src/playbooks" ]] || return 1
  cat >"$pb" <<YML
---
- name: Sonde du workbook (lab/bin/check), supprimée après usage
  hosts: $hote
  gather_facts: false
  roles:
    - role: base
  tasks:
    - name: Valeur effective
      ansible.builtin.debug:
        msg: "WBSONDE={{ $var }}"
      tags: [wb_sonde]
YML
  sortie="$(_m04x_ansible ansible-playbook playbooks/.wb-sonde-check.yml --check --tags wb_sonde 2>&1)" || true
  rm -f -- "$pb"
  sed -nE 's/.*"WBSONDE=([^"]*)".*/\1/p' <<<"$sortie" | head -n 1
}

# _m04x_aucune_panne_active EXX… — aucune des pannes listées (ou M04-* si aucune) n'est marquée.
_m04x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    ! ls "$d"/M04-E* >/dev/null 2>&1
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M04-$e" ]] || return 1
  done
}
