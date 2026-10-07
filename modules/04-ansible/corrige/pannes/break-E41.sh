# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# break-E41.sh — M04-E41 « Panne : le playbook est devenu très lent »
#
# Variantes :
#   1. copie de travail : ansible.cfg, forks = 1 (« débogage, une machine à la fois », oublié) ;
#   2. copie de travail : ansible.cfg, [ssh_connection] ssh_args sans multiplexage
#      (-o ControlMaster=no, « contournement d'un socket de contrôle bloqué ») et pipelining = False
#      dans chaque section qui le définissait (+ [ssh_connection]) ;
#   3. copie de travail : inventories/lab/group_vars/all/zz-ssh-debug.yml définit ansible_ssh_args
#      (sans multiplexage) et ansible_pipelining: false : ansible.cfg est intact, mais les variables
#      de connexion l'emportent sur la configuration ;
#   4. git01 : /etc/pam.d/sudo appelle (pam_exec, session) un script d'« audit HDS » qui envoie un
#      message syslog TCP vers 10.10.20.250, adresse sans machine : chaque sudo attend ~3 s à
#      l'ouverture et à la fermeture de session ; avec la stratégie linear, tout le playbook
#      attend git01 à chaque tâche.
# Sauvegardes : ~/.local/state/workbook/M04-E41/ (copie de travail) ; /var/lib/workbook/M04-E41.*
# sur git01. Annulation : seuls les fichiers encore dans l'état posé par la panne sont rétablis.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# forks effectif = 1 ?
_e41_forks_1() {
  local d
  d="$(m04_ansible ansible-config dump --only-changed 2>/dev/null)" || true
  grep -Eq '^DEFAULT_FORKS\(.*\) = 1$' <<<"$d"
}

_mE41_une() {
  local n="$1" cfg="$_M04_SRC/ansible.cfg" s
  case "$n" in
    1)
      _e41_forks_1 && return 10
      m04_sauver E41 "$cfg" || return 1
      m04_ini_set "$cfg" defaults forks 1 "Lucas : débogage du rôle pare_feu, une machine à la fois" || return 1
      m04_noter E41 "$cfg"
      m04_journal E41 "ansible.cfg : forks = 1"
      ;;
    2)
      m04_sauver E41 "$cfg" || return 1
      m04_ini_set "$cfg" ssh_connection ssh_args "-C -o ControlMaster=no -o ServerAliveInterval=30" \
        "Contournement : « ControlSocket already exists » sur adm01 (Lucas)" || return 1
      while IFS= read -r s; do
        [[ -n "$s" ]] && m04_ini_set "$cfg" "$s" pipelining False
      done < <(m04_ini_sections_avec "$cfg" pipelining)
      m04_ini_set "$cfg" ssh_connection pipelining False || return 1
      m04_noter E41 "$cfg"
      m04_journal E41 "ansible.cfg : ssh_args sans multiplexage, pipelining False"
      ;;
    3)
      [[ -e "$_M04_SRC/inventories/lab/group_vars/all/zz-ssh-debug.yml" ]] && return 10
      [[ -d "$_M04_SRC/inventories/lab/group_vars/all" ]] || return 10
      m04_poser E41 "$_M04_SRC/inventories/lab/group_vars/all/zz-ssh-debug.yml" <<'YML' || return 1
---
# Débogage des coupures SSH vers gw01 (Lucas) : une connexion neuve par tâche, plus lisible
# dans les journaux de sshd.
ansible_ssh_args: "-C -o ControlMaster=no -o ServerAliveInterval=30"
ansible_pipelining: false
YML
      m04_journal E41 "group_vars/all/zz-ssh-debug.yml : multiplexage et pipelining désactivés par variables"
      ;;
    4)
      local rc=0
      m04_wb_exec git01 >/dev/null <<'EOF' || rc=$?
grep -q 'pam_exec' /etc/pam.d/sudo && exit 10
s=/usr/local/sbin/ms-audit-sudo
sauver /etc/pam.d/sudo
sauver "$s"
cat >"$s" <<'SCRIPT'
#!/bin/sh
# Audit HDS : trace de chaque session sudo vers le collecteur central (InfoGér, AUD-114).
logger --tcp -n 10.10.20.250 -P 514 -t audit-sudo "type=$PAM_TYPE utilisateur=$PAM_RUSER cible=$PAM_USER service=$PAM_SERVICE" 2>/dev/null
exit 0
SCRIPT
chmod 755 "$s"
printf '%s\n' '# Audit HDS (AUD-114) : journalisation centralisée des élévations' \
  'session optional pam_exec.so quiet /usr/local/sbin/ms-audit-sudo' >>/etc/pam.d/sudo
noter_injecte /etc/pam.d/sudo
noter_injecte "$s"
journal "pam_exec ajouté à /etc/pam.d/sudo (collecteur syslog sans machine)"
EOF
      ((rc == 0)) || return "$rc"
      ;;
  esac
}

# Durée (s) d'un sudo sur git01, mesurée sur place.
_e41_duree_sudo() {
  remote git01 's=$(date +%s%N); sudo -n true; e=$(date +%s%N); echo $(( (e - s) / 1000000000 ))' 2>/dev/null || echo 0
}

_e41_injecter() {
  m04_prerequis || return 1
  m04_instantane E41
  m04_essayer E41 4 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }
panne_E41_v4() { _e41_injecter 4; }

verifier_E41() {
  local d
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) _e41_forks_1 ;;
    2) [[ "$(m04_ansible ansible-config dump --only-changed -t connection ssh 2>/dev/null)" == *"ControlMaster=no"* ]] ;;
    3) m04_ansible ansible-inventory --host dns01 2>/dev/null | jq -e '(.ansible_ssh_args // "") | test("ControlMaster=no")' >/dev/null ;;
    4)
      d="$(_e41_duree_sudo)"
      [[ "$d" =~ ^[0-9]+$ ]] && ((d >= 2))
      ;;
    *) return 1 ;;
  esac
}

annuler_E41() {
  m04_restaurer E41
  m04_wb_exec git01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
journal "annulation : /etc/pam.d/sudo et script d'audit rétablis (sauf réparation)"
exit 0
EOF
}

resume_E41() {
  echo "Le playbook du socle, qui prenait quelques minutes, en prend maintenant beaucoup plus, sans erreur."
}

symptome_E41() {
  wb_symptome "Ticket INC-3147 — De : Karim Benali" \
    "Le passage complet de site.yml prenait environ 4 minutes. Depuis hier, c'est interminable" \
    "(j'ai arrêté au bout de 20 minutes) : aucune erreur, tout est « ok », mais chaque tâche se" \
    "traîne. Le pipeline de dérive dépasse son délai. Trouve ce qui ralentit, PROUVE-le par la" \
    "mesure (pas d'intuition), et donne-moi les chiffres avant/après." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 04 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E41 4 "$@"; }
fi
