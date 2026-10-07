# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M04-E35 « Panne : UNREACHABLE sur une partie du socle »
#
# Variantes (une seule machine touchée à chaque fois) :
#   1. git01 : clés d'hôte SSH régénérées (« réinstallation » d'InfoGér) — SSH puis Ansible refusent
#      la connexion (identification de l'hôte changée) ; touche aussi git@git01 (push Git) ;
#   2. copie de travail : inventories/lab/group_vars/role_runner/zz-connexion.yml impose
#      ansible_user: root (« la doc de GitLab Runner dit root ») — runner01 refuse root ;
#   3. copie de travail : inventories/lab/host_vars/dns01/zz-migration.yml fixe ansible_host sur
#      10.10.20.16 (brouillon de dns02, M06, recopié au mauvais endroit) — aucune machine n'y répond ;
#   4. runner01 : compte admin expiré (chage -E 0, « revue des comptes ») — sshd refuse la session.
# Sauvegardes : clés d'hôte de git01 et date d'expiration de admin dans /var/lib/workbook/M04-E35.*
# (git01, runner01) ; fichiers de la copie de travail dans ~/.local/state/workbook/M04-E35/.
# Annulation : v1 et v4 par l'agent QEMU (SSH est justement en cause) ; rien n'est rétabli qui a
# déjà été réparé (known_hosts mis à jour → nouvelles clés gardées ; compte déjà réactivé ;
# fichier d'inventaire modifié ou supprimé).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# _e35_cible N — hôte d'inventaire touché par la variante N
_e35_cible() {
  case "$1" in
    1) echo git01 ;;
    2 | 4) echo runner01 ;;
    3) echo dns01 ;;
  esac
}

# _e35_ping HÔTE — 0 si Ansible joint l'hôte (module ping, sans élévation).
_e35_ping() {
  local o
  o="$(m04_ansible ansible "$1" -m ansible.builtin.ping -o 2>/dev/null)" || return 1
  grep -Eq "^$1 \| SUCCESS" <<<"$o"
}

_e35_precondition() {
  m04_prerequis || return 1
  local h
  for h in git01 runner01 dns01; do
    if ! _e35_ping "$h"; then
      wb_avert "Ansible ne joint déjà pas $h avant la panne : lab/bin/check 04 35"
      return 1
    fi
  done
}

_mE35_une() {
  local n="$1" h
  h="$(_e35_cible "$n")"
  case "$n" in
    1)
      wb_exec git01 >/dev/null <<'EOF' || return 1
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || { echo "aucune clé d'hôte sur git01" >&2; exit 1; }
for f in /etc/ssh/ssh_host_*; do sauver "$f"; done
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null
systemctl restart ssh
journal "clés d'hôte SSH régénérées (anciennes sauvegardées)"
EOF
      ;;
    2)
      m04_poser E35 "$_M04_SRC/inventories/lab/group_vars/role_runner/zz-connexion.yml" <<'YML' || return 1
---
# Connexion à runner01 : la documentation de GitLab Runner installe et enregistre le runner
# en root, on se connecte donc directement en root (Lucas, CHG-583).
ansible_user: root
YML
      m04_journal E35 "group_vars/role_runner/zz-connexion.yml : ansible_user root"
      ;;
    3)
      m04_poser E35 "$_M04_SRC/inventories/lab/host_vars/dns01/zz-migration.yml" <<'YML' || return 1
---
# Préparation de la bascule DNS (M06) : adresse du futur serveur.
ansible_host: 10.10.20.16
YML
      m04_journal E35 "host_vars/dns01/zz-migration.yml : ansible_host 10.10.20.16"
      ;;
    4)
      wb_exec runner01 >/dev/null <<'EOF' || return 1
e="$(getent shadow admin | cut -d: -f8)"
[ -f "$WB_DIR/M04-E35.expire" ] || printf '%s\n' "${e:-vide}" >"$WB_DIR/M04-E35.expire"
chage -E 0 admin
journal "compte admin expiré (ancienne valeur : ${e:-vide})"
EOF
      ;;
  esac
  m04_fermer_ssh "$h"
  sleep 2
  if _e35_ping "$h"; then
    # Variante sans effet sur ce lab (ex. dossier host_vars chargé avant un autre fichier) : défaire.
    _e35_defaire "$n"
    return 10
  fi
}

# _e35_defaire N — retire la variante N (utilisé par l'annulation et si une variante est sans effet).
_e35_defaire() {
  case "$1" in
    1)
      # Si adm01 accepte déjà les NOUVELLES clés (known_hosts réparé), on les garde.
      if m04_ssh_ok git01; then
        m04_journal E35 "annulation : known_hosts déjà mis à jour pour git01, nouvelles clés conservées"
        wb_exec git01 >/dev/null <<'EOF' || true
rm -f "$WB_DIR/$WB_EX".*_etc_ssh_ssh_host_* "$WB_DIR/$WB_EX.manifeste"
journal "annulation : nouvelles clés d'hôte conservées (réparation de l'apprenant)"
EOF
      else
        m04_wb_exec_invite "${_M04_VMID[git01]}" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01 (agent QEMU)"
restaurer_fichiers
systemctl restart ssh
journal "annulation : anciennes clés d'hôte remises"
EOF
      fi
      m04_fermer_ssh git01
      ;;
    2 | 3) m04_restaurer E35 ;;
    4)
      m04_wb_exec_invite "${_M04_VMID[runner01]}" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01 (agent QEMU)"
[ -f "$WB_DIR/M04-E35.expire" ] || exit 0
actuel="$(getent shadow admin | cut -d: -f8)"
if [ -n "$actuel" ] && [ "$actuel" -le "$(( $(date +%s) / 86400 ))" ]; then
  ancien="$(cat "$WB_DIR/M04-E35.expire")"
  if [ "$ancien" = vide ]; then chage -E -1 admin; else chage -E "$ancien" admin; fi
  journal "annulation : expiration du compte admin rétablie ($ancien)"
else
  journal "annulation : compte admin déjà réactivé (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/M04-E35.expire"
EOF
      m04_fermer_ssh runner01
      ;;
  esac
}

_e35_injecter() {
  _e35_precondition || return 1
  m04_instantane E35
  m04_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

verifier_E35() {
  local h
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  h="$(_e35_cible "${WB_VAR:-0}")"
  [[ -n "$h" ]] && ! _e35_ping "$h"
}

annuler_E35() {
  # Chaque élément ne bouge que s'il porte encore la marque de la panne : on peut tout tenter.
  local v="${WB_VAR:-}"
  if [[ "$v" =~ ^[1-4]$ ]]; then
    _e35_defaire "$v"
  else
    m04_restaurer E35
  fi
}

resume_E35() {
  echo "Ansible renvoie UNREACHABLE sur une partie du socle, les autres machines répondent normalement."
}

symptome_E35() {
  wb_symptome "Ticket INC-3141 — De : Julien Petit" \
    "Je voulais passer le playbook du socle en vérification (--check) avant la mise à jour de" \
    "ce soir : une des machines sort en « UNREACHABLE! », les autres répondent normalement." \
    "Je n'ai rien changé au projet, et personne ne sait me dire ce qui a bougé." \
    "La mise à jour de ce soir doit passer sur TOUT le socle." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 04 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E35 4 "$@"; }
fi
